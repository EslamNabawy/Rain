use std::sync::OnceLock;
use std::time::Duration;

use anyhow::{bail, Context, Result};
use iroh::{
    endpoint::{presets, Connection, VarInt},
    Endpoint, EndpointAddr,
};
use serde::{Deserialize, Serialize};

use crate::{
    framing::{
        encoded_frame_len, read_frame, read_hello, verify_hello, write_frame, write_hello,
        RainIrohFrame, RainIrohHello,
    },
    state::{IrohPeerConnection, IrohRuntimeState, SharedIrohRuntimeState},
};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct IrohEndpointInfo {
    pub node_id: String,
    pub endpoint_addr: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct IrohEvent {
    pub event_type: String,
    pub peer_id: String,
    pub channel: Option<String>,
    pub payload: Option<Vec<u8>>,
    pub route: Option<String>,
    pub rtt_ms: Option<f64>,
    pub error: Option<String>,
}

static RUNTIME_STATE: OnceLock<SharedIrohRuntimeState> = OnceLock::new();

fn runtime_state() -> &'static SharedIrohRuntimeState {
    RUNTIME_STATE
        .get_or_init(|| std::sync::Arc::new(tokio::sync::Mutex::new(IrohRuntimeState::default())))
}

pub async fn iroh_start_endpoint(username: String, alpn: String) -> Result<IrohEndpointInfo> {
    start_endpoint_in_state(runtime_state(), username, alpn).await
}

pub async fn iroh_stop_endpoint() -> Result<()> {
    stop_endpoint_in_state(runtime_state()).await
}

pub async fn iroh_connect_peer(
    peer_id: String,
    endpoint_addr: String,
    expected_node_id: String,
    alpn: String,
    connect_attempt_id: String,
    session_secret: String,
) -> Result<()> {
    connect_peer_in_state(
        runtime_state(),
        peer_id,
        endpoint_addr,
        expected_node_id,
        alpn,
        connect_attempt_id,
        session_secret,
    )
    .await
}

pub async fn iroh_accept_peer(
    peer_id: String,
    expected_node_id: String,
    alpn: String,
    connect_attempt_id: String,
    session_secret: String,
) -> Result<()> {
    accept_peer_in_state(
        runtime_state(),
        peer_id,
        expected_node_id,
        alpn,
        connect_attempt_id,
        session_secret,
    )
    .await
}

pub async fn iroh_disconnect_peer(peer_id: String) -> Result<()> {
    disconnect_peer_in_state(runtime_state(), peer_id).await
}

pub async fn iroh_send(peer_id: String, channel: String, payload: Vec<u8>) -> Result<()> {
    send_frame_in_state(
        runtime_state(),
        peer_id,
        RainIrohFrame::data(&channel, payload),
    )
    .await
}

pub async fn iroh_buffered_amount(peer_id: String, channel: String) -> Result<u64> {
    Ok(*runtime_state()
        .lock()
        .await
        .pending_bytes
        .get(&pending_key(&peer_id, &channel))
        .unwrap_or(&0))
}

pub fn iroh_event_stream(sink: crate::frb_generated::StreamSink<String>) -> Result<()> {
    let (tx, mut rx) = tokio::sync::mpsc::unbounded_channel::<IrohEvent>();
    let state = runtime_state().clone();
    tokio::spawn(async move {
        state.lock().await.event_tx = Some(tx);
        while let Some(event) = rx.recv().await {
            match serde_json::to_string(&event) {
                Ok(encoded) => {
                    let _ = sink.add(encoded);
                }
                Err(error) => {
                    let _ = sink.add(format!(
                        r#"{{"event_type":"error","peer_id":"","error":"{}"}}"#,
                        error
                    ));
                }
            }
        }
    });
    Ok(())
}

pub(crate) async fn start_endpoint_in_state(
    state: &SharedIrohRuntimeState,
    username: String,
    alpn: String,
) -> Result<IrohEndpointInfo> {
    let endpoint = Endpoint::builder(presets::N0)
        .alpns(vec![alpn.into_bytes()])
        .bind()
        .await
        .context("bind iroh endpoint")?;

    // Do not let startup hang forever offline. `addr()` is still useful with a
    // node id and local candidates; relay details are added if `online()` wins.
    let _ = tokio::time::timeout(Duration::from_secs(3), endpoint.online()).await;

    let node_id = endpoint.id().to_string();
    let endpoint_addr =
        serde_json::to_string(&endpoint.addr()).context("serialize iroh endpoint address")?;

    let mut guard = state.lock().await;
    if let Some(old) = guard.endpoint.take() {
        old.close().await;
    }
    for peer in guard.peers.drain().map(|(_, peer)| peer) {
        peer.conn
            .close(VarInt::from_u32(0), b"rain endpoint restart");
    }
    guard.endpoint = Some(endpoint);
    guard.username = Some(normalize_name(&username));
    guard.pending_bytes.clear();

    Ok(IrohEndpointInfo {
        node_id,
        endpoint_addr,
    })
}

pub(crate) async fn stop_endpoint_in_state(state: &SharedIrohRuntimeState) -> Result<()> {
    let mut guard = state.lock().await;
    for peer in guard.peers.drain().map(|(_, peer)| peer) {
        peer.conn.close(VarInt::from_u32(0), b"rain shutdown");
    }
    if let Some(endpoint) = guard.endpoint.take() {
        endpoint.close().await;
    }
    guard.pending_bytes.clear();
    Ok(())
}

pub(crate) async fn connect_peer_in_state(
    state: &SharedIrohRuntimeState,
    peer_id: String,
    endpoint_addr: String,
    expected_node_id: String,
    alpn: String,
    connect_attempt_id: String,
    session_secret: String,
) -> Result<()> {
    let (endpoint, local_username) = endpoint_and_username_from_state(state).await?;
    let addr: EndpointAddr =
        serde_json::from_str(&endpoint_addr).context("parse iroh endpoint address")?;
    let conn = endpoint
        .connect(addr, alpn.as_bytes())
        .await
        .context("connect iroh peer")?;
    validate_remote(&conn, &expected_node_id, &alpn)?;
    authenticate_dialer(
        &conn,
        &endpoint,
        &local_username,
        &peer_id,
        &expected_node_id,
        &connect_attempt_id,
        &session_secret,
    )
    .await?;
    register_connection(state, peer_id, conn).await
}

pub(crate) async fn accept_peer_in_state(
    state: &SharedIrohRuntimeState,
    peer_id: String,
    expected_node_id: String,
    alpn: String,
    connect_attempt_id: String,
    session_secret: String,
) -> Result<()> {
    let (endpoint, local_username) = endpoint_and_username_from_state(state).await?;
    let incoming = endpoint.accept().await.context("accept iroh connection")?;
    let conn = incoming.await.context("complete iroh accept")?;
    validate_remote(&conn, &expected_node_id, &alpn)?;
    authenticate_acceptor(
        &conn,
        &endpoint,
        &local_username,
        &peer_id,
        &expected_node_id,
        &connect_attempt_id,
        &session_secret,
    )
    .await?;
    register_connection(state, peer_id, conn).await
}

pub(crate) async fn disconnect_peer_in_state(
    state: &SharedIrohRuntimeState,
    peer_id: String,
) -> Result<()> {
    let peer = state.lock().await.peers.remove(&peer_id);
    if let Some(peer) = peer {
        peer.conn.close(VarInt::from_u32(0), b"rain disconnect");
    }
    remove_pending_for_peer(state, &peer_id).await;
    emit_event(
        state,
        IrohEvent {
            event_type: "disconnected".to_string(),
            peer_id,
            channel: None,
            payload: None,
            route: None,
            rtt_ms: None,
            error: None,
        },
    )
    .await;
    Ok(())
}

pub(crate) async fn send_frame_in_state(
    state: &SharedIrohRuntimeState,
    peer_id: String,
    frame: RainIrohFrame,
) -> Result<()> {
    let pending_len = encoded_frame_len(&frame)? as u64;
    add_pending_bytes(state, &peer_id, &frame.channel, pending_len).await;
    let result = write_frame_to_peer(state, &peer_id, &frame).await;
    remove_pending_bytes(state, &peer_id, &frame.channel, pending_len).await;
    result
}

async fn write_frame_to_peer(
    state: &SharedIrohRuntimeState,
    peer_id: &str,
    frame: &RainIrohFrame,
) -> Result<()> {
    let conn = connection_from_state(state, peer_id).await?;
    let (mut send_stream, _recv_stream) = conn.open_bi().await.context("open iroh send stream")?;
    write_frame(&mut send_stream, &frame).await
}

pub(crate) async fn register_connection(
    state: &SharedIrohRuntimeState,
    peer_id: String,
    conn: Connection,
) -> Result<()> {
    let diagnostics = diagnostics_event(&peer_id, &conn);
    state
        .lock()
        .await
        .peers
        .insert(peer_id.clone(), IrohPeerConnection { conn: conn.clone() });
    emit_event(state, diagnostics).await;

    let state_for_loop = state.clone();
    tokio::spawn(async move {
        read_loop(state_for_loop, peer_id, conn).await;
    });
    Ok(())
}

async fn read_loop(state: SharedIrohRuntimeState, peer_id: String, conn: Connection) {
    loop {
        let accepted = conn.accept_bi().await;
        let (mut send_stream, mut recv_stream) = match accepted {
            Ok(streams) => streams,
            Err(error) => {
                emit_event(
                    &state,
                    IrohEvent {
                        event_type: "disconnected".to_string(),
                        peer_id: peer_id.clone(),
                        channel: None,
                        payload: None,
                        route: None,
                        rtt_ms: None,
                        error: Some(error.to_string()),
                    },
                )
                .await;
                break;
            }
        };

        match read_frame(&mut recv_stream).await {
            Ok(frame) => {
                let _ = send_stream.finish();
                emit_event(
                    &state,
                    IrohEvent {
                        event_type: "data".to_string(),
                        peer_id: peer_id.clone(),
                        channel: Some(frame.channel),
                        payload: Some(frame.payload),
                        route: None,
                        rtt_ms: None,
                        error: None,
                    },
                )
                .await;
            }
            Err(error) => {
                emit_event(
                    &state,
                    IrohEvent {
                        event_type: "error".to_string(),
                        peer_id: peer_id.clone(),
                        channel: None,
                        payload: None,
                        route: None,
                        rtt_ms: None,
                        error: Some(error.to_string()),
                    },
                )
                .await;
            }
        }
    }
}

async fn endpoint_and_username_from_state(
    state: &SharedIrohRuntimeState,
) -> Result<(Endpoint, String)> {
    let guard = state.lock().await;
    let endpoint = guard
        .endpoint
        .clone()
        .context("iroh endpoint is not started")?;
    let username = guard
        .username
        .clone()
        .context("iroh username is not initialized")?;
    Ok((endpoint, username))
}

async fn connection_from_state(
    state: &SharedIrohRuntimeState,
    peer_id: &str,
) -> Result<Connection> {
    state
        .lock()
        .await
        .peers
        .get(peer_id)
        .map(|peer| peer.conn.clone())
        .with_context(|| format!("no active iroh connection for {peer_id}"))
}

async fn authenticate_dialer(
    conn: &Connection,
    endpoint: &Endpoint,
    local_username: &str,
    peer_id: &str,
    expected_node_id: &str,
    connect_attempt_id: &str,
    session_secret: &str,
) -> Result<()> {
    let (mut send_stream, mut recv_stream) =
        conn.open_bi().await.context("open iroh hello stream")?;
    let local_node_id = endpoint.id().to_string();
    let hello = RainIrohHello::signed(
        connect_attempt_id,
        local_username,
        peer_id,
        &local_node_id,
        session_secret,
    )?;
    write_hello(&mut send_stream, &hello).await?;
    let remote = read_hello(&mut recv_stream).await?;
    verify_hello(
        &remote,
        peer_id,
        local_username,
        expected_node_id,
        connect_attempt_id,
        session_secret,
    )
}

async fn authenticate_acceptor(
    conn: &Connection,
    endpoint: &Endpoint,
    local_username: &str,
    peer_id: &str,
    expected_node_id: &str,
    connect_attempt_id: &str,
    session_secret: &str,
) -> Result<()> {
    let (mut send_stream, mut recv_stream) =
        conn.accept_bi().await.context("accept iroh hello stream")?;
    let remote = read_hello(&mut recv_stream).await?;
    verify_hello(
        &remote,
        peer_id,
        local_username,
        expected_node_id,
        connect_attempt_id,
        session_secret,
    )?;
    let local_node_id = endpoint.id().to_string();
    let hello = RainIrohHello::signed(
        connect_attempt_id,
        local_username,
        peer_id,
        &local_node_id,
        session_secret,
    )?;
    write_hello(&mut send_stream, &hello).await
}

fn validate_remote(conn: &Connection, expected_node_id: &str, alpn: &str) -> Result<()> {
    let actual_node_id = conn.remote_id().to_string();
    if !expected_node_id.trim().is_empty() && actual_node_id != expected_node_id {
        conn.close(VarInt::from_u32(1), b"unexpected iroh peer");
        bail!("unexpected iroh peer node id");
    }
    if conn.alpn() != alpn.as_bytes() {
        conn.close(VarInt::from_u32(1), b"unexpected iroh alpn");
        bail!("unexpected iroh ALPN");
    }
    Ok(())
}

fn diagnostics_event(peer_id: &str, conn: &Connection) -> IrohEvent {
    let paths = conn.paths();
    let selected = paths.iter().find(|path| path.is_selected());
    let fallback = paths.iter().next();
    let path = selected.or(fallback);
    let route = path.as_ref().map(|path| {
        if path.is_relay() {
            "relay"
        } else if path.is_ip() {
            "direct"
        } else {
            "unknown"
        }
    });
    let rtt_ms = path.map(|path| path.rtt().as_secs_f64() * 1000.0);

    IrohEvent {
        event_type: "diagnostics".to_string(),
        peer_id: peer_id.to_string(),
        channel: None,
        payload: None,
        route: route.map(str::to_string),
        rtt_ms,
        error: None,
    }
}

pub(crate) async fn emit_event(state: &SharedIrohRuntimeState, event: IrohEvent) {
    let tx = state.lock().await.event_tx.clone();
    if let Some(tx) = tx {
        let _ = tx.send(event);
    }
}

fn pending_key(peer_id: &str, channel: &str) -> String {
    format!("{}\u{0}{}", normalize_name(peer_id), channel)
}

async fn add_pending_bytes(
    state: &SharedIrohRuntimeState,
    peer_id: &str,
    channel: &str,
    amount: u64,
) {
    let key = pending_key(peer_id, channel);
    let mut guard = state.lock().await;
    *guard.pending_bytes.entry(key).or_insert(0) += amount;
}

async fn remove_pending_bytes(
    state: &SharedIrohRuntimeState,
    peer_id: &str,
    channel: &str,
    amount: u64,
) {
    let key = pending_key(peer_id, channel);
    let mut guard = state.lock().await;
    if let Some(current) = guard.pending_bytes.get_mut(&key) {
        *current = current.saturating_sub(amount);
        if *current == 0 {
            guard.pending_bytes.remove(&key);
        }
    }
}

async fn remove_pending_for_peer(state: &SharedIrohRuntimeState, peer_id: &str) {
    let prefix = format!("{}\u{0}", normalize_name(peer_id));
    state
        .lock()
        .await
        .pending_bytes
        .retain(|key, _| !key.starts_with(&prefix));
}

fn normalize_name(value: &str) -> String {
    value.trim().to_ascii_lowercase()
}
