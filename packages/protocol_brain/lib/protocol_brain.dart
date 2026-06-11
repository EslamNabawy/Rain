/// # protocol_brain.dart
///
/// Public barrel export file for the protocol_brain package. Re-exports all peer_core types and protocol_brain adapters, connection management, session handling, signaling, and voice call coordination types.
///
/// **Key types:** Re-exports: PeerCore, PeerConfig, CallMediaConnection, VoiceMediaConnection, and ~30+ types from peer_core + protocol_brain
///
/// **Depends on:** peer_core, protocol_brain/src/*, protocol_brain/adapters/*

export 'package:peer_core/peer_core.dart'
    show
        PeerAddressFamily,
        PeerConfig,
        PeerDebugEventSink,
        PeerConnectionRoute,
        PeerIceTransportPolicy,
        PeerRemoteTrack,
        PeerRouteKind,
        TurnReadiness,
        TurnReadinessResult,
        TurnUnavailableException,
        FlutterWebRTCBridge,
        PlatformBridge,
        StorageBackend,
        MemoryStorageBackend,
        VoiceMediaAudioLevel,
        VoiceMediaAudioLevelSource,
        VoiceMediaOutputRoute,
        CallIceCandidate,
        CallMediaConnection,
        CallMediaDiagnostics,
        CallMediaException,
        CallMediaFailureReason,
        CallMediaKind,
        CallMediaOutputRoute,
        CallMediaPhase,
        CallMediaProcessingConfig,
        CallMediaState,
        CallRemoteMediaTrack,
        CallSessionDescription,
        CallVideoOptimizationProfile,
        MediaInterruptionEvent,
        MediaInterruptionType,
        DefaultCallMediaConnection,
        VoiceIceCandidate,
        VoiceMediaDiagnostics,
        VoiceMediaConnection,
        VoiceMediaPhase,
        VoiceMediaState,
        VoiceRemoteAudioTrack,
        VoiceSessionDescription;

export 'adapters/firebase_adapter.dart';
export 'adapters/signaling_adapter.dart';
export 'adapters/signaling_cipher.dart';
export 'src/connection_memory.dart';
export 'src/connection_request_adapter.dart';
export 'src/connection_request_backend_mode.dart';
export 'src/connection_request_contract.dart';
export 'src/connection_request_rtdb_adapter.dart';
export 'src/default_protocol_brain.dart';
export 'src/ice_candidate_batcher.dart';
export 'src/protocol_brain_impl.dart';
export 'src/session_manager.dart';
export 'src/signaling_cost_budget.dart';
export 'src/testing/fake_connection_request_adapter.dart';
export 'src/voice_call_cleanup_janitor.dart';
export 'src/voice_call_frame.dart';
export 'src/voice_call_clock.dart';
export 'src/voice_call_session.dart';
export 'src/voice_signaling_contract.dart';
