use rust_lib_rain::framing::{
    decode_frame, encode_frame, verify_hello, RainIrohFrame, RainIrohHello,
};

#[test]
fn frame_codec_round_trips_chat_payload() {
    let frame = RainIrohFrame::data("rain.chat", b"hello".to_vec());
    let encoded = encode_frame(&frame).expect("encode");
    let decoded = decode_frame(&encoded).expect("decode");

    assert_eq!(decoded.channel, "rain.chat");
    assert_eq!(decoded.payload, b"hello");
}

#[test]
fn frame_codec_rejects_oversized_length() {
    let oversized = vec![0xff, 0xff, 0xff, 0xff];
    assert!(decode_frame(&oversized).is_err());
}

#[test]
fn signed_hello_verifies_expected_attempt_and_peer() {
    let hello = RainIrohHello::signed(
        "attempt-1",
        "Alice",
        "Bob",
        "alice-node",
        "test-session-secret",
    )
    .expect("signed hello");

    verify_hello(
        &hello,
        "alice",
        "bob",
        "alice-node",
        "attempt-1",
        "test-session-secret",
    )
    .expect("hello verifies");
}

#[test]
fn signed_hello_rejects_wrong_attempt_or_secret() {
    let hello = RainIrohHello::signed(
        "attempt-1",
        "alice",
        "bob",
        "alice-node",
        "test-session-secret",
    )
    .expect("signed hello");

    assert!(verify_hello(
        &hello,
        "alice",
        "bob",
        "alice-node",
        "attempt-2",
        "test-session-secret",
    )
    .is_err());
    assert!(verify_hello(
        &hello,
        "alice",
        "bob",
        "alice-node",
        "attempt-1",
        "wrong-secret",
    )
    .is_err());
}
