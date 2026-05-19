use anyhow::{bail, Context, Result};
use base64::{
    engine::general_purpose::{URL_SAFE, URL_SAFE_NO_PAD},
    Engine as _,
};
use hmac::{Hmac, Mac};
use iroh::endpoint::{RecvStream, SendStream};
use rand::RngCore;
use serde::{Deserialize, Serialize};
use sha2::Sha256;

const MAX_FRAME_BYTES: usize = 256 * 1024;
const MAX_WIRE_FRAME_BYTES: usize = MAX_FRAME_BYTES + 4;
type HmacSha256 = Hmac<Sha256>;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct RainIrohFrame {
    pub frame_type: String,
    pub protocol_version: u16,
    pub channel: String,
    pub payload: Vec<u8>,
}

impl RainIrohFrame {
    pub fn data(channel: &str, payload: Vec<u8>) -> Self {
        Self {
            frame_type: "rain.iroh.data".to_string(),
            protocol_version: 1,
            channel: channel.to_string(),
            payload,
        }
    }

    pub fn hello(hello: &RainIrohHello) -> Result<Self> {
        Ok(Self {
            frame_type: "rain.iroh.hello".to_string(),
            protocol_version: 1,
            channel: "rain.ctrl".to_string(),
            payload: serde_json::to_vec(hello).context("serialize iroh hello")?,
        })
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct RainIrohHello {
    pub frame_type: String,
    pub protocol_version: u16,
    pub connect_attempt_id: String,
    pub from: String,
    pub to: String,
    pub node_id: String,
    pub nonce: String,
    pub hmac: String,
}

impl RainIrohHello {
    pub fn signed(
        connect_attempt_id: &str,
        from: &str,
        to: &str,
        node_id: &str,
        session_secret: &str,
    ) -> Result<Self> {
        let mut nonce = [0_u8; 16];
        rand::rngs::OsRng.fill_bytes(&mut nonce);
        let nonce = URL_SAFE_NO_PAD.encode(nonce);
        let hmac = sign_hello(
            connect_attempt_id,
            from,
            to,
            node_id,
            &nonce,
            session_secret,
        )?;
        Ok(Self {
            frame_type: "rain.iroh.hello".to_string(),
            protocol_version: 1,
            connect_attempt_id: connect_attempt_id.to_string(),
            from: normalize_name(from),
            to: normalize_name(to),
            node_id: node_id.to_string(),
            nonce,
            hmac,
        })
    }
}

pub fn encode_frame(frame: &RainIrohFrame) -> Result<Vec<u8>> {
    let body = serde_json::to_vec(frame).context("serialize iroh frame")?;
    if body.len() > MAX_FRAME_BYTES {
        bail!("iroh frame too large");
    }

    let len = u32::try_from(body.len()).context("frame length overflow")?;
    let mut out = len.to_be_bytes().to_vec();
    out.extend(body);
    Ok(out)
}

pub fn encoded_frame_len(frame: &RainIrohFrame) -> Result<usize> {
    encode_frame(frame).map(|bytes| bytes.len())
}

pub fn decode_frame(bytes: &[u8]) -> Result<RainIrohFrame> {
    if bytes.len() < 4 {
        bail!("iroh frame missing length prefix");
    }

    let mut prefix = [0u8; 4];
    prefix.copy_from_slice(&bytes[..4]);
    let len = u32::from_be_bytes(prefix) as usize;
    if len > MAX_FRAME_BYTES {
        bail!("iroh frame too large");
    }
    if bytes.len() != len + 4 {
        bail!("iroh frame length mismatch");
    }

    serde_json::from_slice(&bytes[4..]).context("decode iroh frame")
}

pub async fn write_frame(send_stream: &mut SendStream, frame: &RainIrohFrame) -> Result<()> {
    let encoded = encode_frame(frame)?;
    send_stream
        .write_all(&encoded)
        .await
        .context("write iroh frame")?;
    send_stream.finish().context("finish iroh frame stream")?;
    Ok(())
}

pub async fn read_frame(recv_stream: &mut RecvStream) -> Result<RainIrohFrame> {
    let encoded = recv_stream
        .read_to_end(MAX_WIRE_FRAME_BYTES)
        .await
        .context("read iroh frame")?;
    decode_frame(&encoded)
}

pub async fn write_hello(send_stream: &mut SendStream, hello: &RainIrohHello) -> Result<()> {
    let frame = RainIrohFrame::hello(hello)?;
    write_frame(send_stream, &frame).await
}

pub async fn read_hello(recv_stream: &mut RecvStream) -> Result<RainIrohHello> {
    let frame = read_frame(recv_stream).await?;
    if frame.frame_type != "rain.iroh.hello" {
        bail!("expected iroh hello frame");
    }
    if frame.protocol_version != 1 {
        bail!("unsupported iroh hello version");
    }
    serde_json::from_slice(&frame.payload).context("decode iroh hello")
}

pub fn verify_hello(
    hello: &RainIrohHello,
    expected_from: &str,
    expected_to: &str,
    expected_node_id: &str,
    connect_attempt_id: &str,
    session_secret: &str,
) -> Result<()> {
    if hello.frame_type != "rain.iroh.hello" {
        bail!("unexpected iroh hello type");
    }
    if hello.protocol_version != 1 {
        bail!("unsupported iroh hello version");
    }
    if hello.connect_attempt_id != connect_attempt_id {
        bail!("unexpected iroh connect attempt");
    }
    if hello.from != normalize_name(expected_from) {
        bail!("unexpected iroh hello sender");
    }
    if hello.to != normalize_name(expected_to) {
        bail!("unexpected iroh hello recipient");
    }
    if !expected_node_id.trim().is_empty() && hello.node_id != expected_node_id {
        bail!("unexpected iroh hello node id");
    }
    let expected = sign_hello(
        &hello.connect_attempt_id,
        &hello.from,
        &hello.to,
        &hello.node_id,
        &hello.nonce,
        session_secret,
    )?;
    if hello.hmac != expected {
        bail!("invalid iroh hello hmac");
    }
    Ok(())
}

fn sign_hello(
    connect_attempt_id: &str,
    from: &str,
    to: &str,
    node_id: &str,
    nonce: &str,
    session_secret: &str,
) -> Result<String> {
    let key = session_key(session_secret);
    let mut mac = HmacSha256::new_from_slice(&key).context("create iroh hello hmac")?;
    mac.update(
        format!(
            "rain.iroh.hello.v1|{}|{}|{}|{}|{}",
            connect_attempt_id,
            normalize_name(from),
            normalize_name(to),
            node_id,
            nonce
        )
        .as_bytes(),
    );
    Ok(URL_SAFE_NO_PAD.encode(mac.finalize().into_bytes()))
}

fn session_key(session_secret: &str) -> Vec<u8> {
    URL_SAFE_NO_PAD
        .decode(session_secret.as_bytes())
        .or_else(|_| URL_SAFE.decode(session_secret.as_bytes()))
        .unwrap_or_else(|_| session_secret.as_bytes().to_vec())
}

fn normalize_name(value: &str) -> String {
    value.trim().to_ascii_lowercase()
}
