use rust_lib_rain::framing::RainIrohFrame;
use rust_lib_rain::test_support::IrohTestNode;

#[tokio::test]
async fn two_endpoints_exchange_chat_frame() -> anyhow::Result<()> {
    let alice = IrohTestNode::start("alice", "rain.p2p.quic.v1").await?;
    let bob = IrohTestNode::start("bob", "rain.p2p.quic.v1").await?;

    let accept = bob.accept_from("alice", alice.node_id(), "attempt-1", "test-session-secret");
    let connect = alice.connect_to(
        "bob",
        bob.endpoint_addr(),
        bob.node_id(),
        "attempt-1",
        "test-session-secret",
    );
    let (accepted, connected) = tokio::join!(accept, connect);
    accepted?;
    connected?;

    alice
        .send_frame(
            "bob",
            RainIrohFrame::data("rain.chat", b"hello from alice".to_vec()),
        )
        .await?;

    let received = bob.next_frame("alice").await?;
    assert_eq!(received.channel, "rain.chat");
    assert_eq!(received.payload, b"hello from alice");

    alice.stop().await?;
    bob.stop().await?;
    Ok(())
}
