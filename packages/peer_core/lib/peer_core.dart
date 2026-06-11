/// # peer_core.dart
///
/// The peer_core library barrel file that re-exports all public APIs including WebRTC transport, media connections, platform bridge, state machine, data channel backpressure, and voice/call media models.
///
/// **Key types:** (barrel export file — see exported modules for types)
///
/// **Depends on:** src/call/, src/voice/, src/data_channel_backpressure.dart, src/default_peer_core.dart, src/models.dart, src/platform_bridge.dart, src/state_machine.dart
export 'src/call/call_media_connection.dart';
export 'src/call/call_media_models.dart';
export 'src/call/media_interruption.dart';
export 'src/data_channel_backpressure.dart';
export 'src/default_peer_core.dart';
export 'src/models.dart';
export 'src/platform_bridge.dart';
export 'src/state_machine.dart';
export 'src/voice/voice_media_connection.dart';
export 'src/voice/voice_media_models.dart';
