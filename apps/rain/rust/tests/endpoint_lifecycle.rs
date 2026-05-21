use iroh::EndpointAddr;
use rust_lib_rain::{iroh_start_endpoint, iroh_stop_endpoint};

#[tokio::test]
async fn endpoint_starts_with_node_id_and_address() {
    let info = iroh_start_endpoint("alice".to_string(), "rain.p2p.quic.v1".to_string())
        .await
        .expect("endpoint starts");

    assert!(!info.node_id.trim().is_empty());
    assert_ne!(info.node_id, "not-started");
    assert!(!info.endpoint_addr.trim().is_empty());
    assert_ne!(info.endpoint_addr, "not-started");

    let parsed: EndpointAddr =
        serde_json::from_str(&info.endpoint_addr).expect("endpoint address is parseable JSON");
    assert_eq!(parsed.id.to_string(), info.node_id);

    iroh_stop_endpoint().await.expect("endpoint stops");
}
