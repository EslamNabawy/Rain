use std::{sync::Arc, time::Duration};

use anyhow::{Context, Result};
use tokio::sync::{mpsc, Mutex};

use crate::{
    api::iroh_transport::{
        accept_peer_in_state, connect_peer_in_state, start_endpoint_in_state,
        stop_endpoint_in_state, IrohEndpointInfo, IrohEvent,
    },
    framing::RainIrohFrame,
    state::{IrohRuntimeState, SharedIrohRuntimeState},
};

pub struct IrohTestNode {
    state: SharedIrohRuntimeState,
    endpoint: IrohEndpointInfo,
    events: Mutex<mpsc::UnboundedReceiver<IrohEvent>>,
    alpn: String,
}

impl IrohTestNode {
    pub async fn start(username: &str, alpn: &str) -> Result<Self> {
        let state = Arc::new(Mutex::new(IrohRuntimeState::default()));
        let (tx, rx) = mpsc::unbounded_channel::<IrohEvent>();
        state.lock().await.event_tx = Some(tx);
        let endpoint =
            start_endpoint_in_state(&state, username.to_string(), alpn.to_string()).await?;

        Ok(Self {
            state,
            endpoint,
            events: Mutex::new(rx),
            alpn: alpn.to_string(),
        })
    }

    pub fn endpoint_addr(&self) -> String {
        self.endpoint.endpoint_addr.clone()
    }

    pub fn node_id(&self) -> String {
        self.endpoint.node_id.clone()
    }

    pub async fn connect_to(
        &self,
        peer_id: &str,
        endpoint_addr: String,
        expected_node_id: String,
        connect_attempt_id: &str,
        session_secret: &str,
    ) -> Result<()> {
        connect_peer_in_state(
            &self.state,
            peer_id.to_string(),
            endpoint_addr,
            expected_node_id,
            self.alpn.clone(),
            connect_attempt_id.to_string(),
            session_secret.to_string(),
        )
        .await
    }

    pub async fn accept_from(
        &self,
        peer_id: &str,
        expected_node_id: String,
        connect_attempt_id: &str,
        session_secret: &str,
    ) -> Result<()> {
        accept_peer_in_state(
            &self.state,
            peer_id.to_string(),
            expected_node_id,
            self.alpn.clone(),
            connect_attempt_id.to_string(),
            session_secret.to_string(),
        )
        .await
    }

    pub async fn send_frame(&self, peer_id: &str, frame: RainIrohFrame) -> Result<()> {
        crate::api::iroh_transport::send_frame_in_state(&self.state, peer_id.to_string(), frame)
            .await
    }

    pub async fn next_frame(&self, peer_id: &str) -> Result<RainIrohFrame> {
        let mut events = self.events.lock().await;
        loop {
            let event = tokio::time::timeout(Duration::from_secs(10), events.recv())
                .await
                .context("wait for test iroh frame")?
                .context("test iroh event stream closed")?;
            if event.event_type != "data" || event.peer_id != peer_id {
                continue;
            }
            return Ok(RainIrohFrame::data(
                event.channel.as_deref().unwrap_or_default(),
                event.payload.unwrap_or_default(),
            ));
        }
    }

    pub async fn stop(&self) -> Result<()> {
        stop_endpoint_in_state(&self.state).await
    }
}
