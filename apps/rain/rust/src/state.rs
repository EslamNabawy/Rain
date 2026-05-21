use std::sync::Arc;

use std::collections::HashMap;

use iroh::{endpoint::Connection, Endpoint};
use tokio::sync::{mpsc, Mutex};

use crate::api::iroh_transport::IrohEvent;

pub struct IrohPeerConnection {
    pub conn: Connection,
}

#[derive(Default)]
pub struct IrohRuntimeState {
    pub username: Option<String>,
    pub endpoint: Option<Endpoint>,
    pub peers: HashMap<String, IrohPeerConnection>,
    pub pending_bytes: HashMap<String, u64>,
    pub event_tx: Option<mpsc::UnboundedSender<IrohEvent>>,
}

pub type SharedIrohRuntimeState = Arc<Mutex<IrohRuntimeState>>;
