/// # rain_runtime_controller.dart
///
/// [RainRuntimeController] is the central runtime orchestrator for Rain. Owns
/// all mutable runtime state: sessions, calls, file transfers, presence
/// subscriptions, and connection requests. Exposes extension-based runtime
/// modules (voice call, file transfer, friend, connection request) and
/// coordinates shutdown via [AppExitCoordinator].
///
/// **Key types:** [RainRuntimeController], [FriendRequestResult], [RuntimeErrorRecorder], [RuntimeEventRecorder]
///
/// **Depends on:** protocol_brain, rain_core, all runtime extensions
library;

// ignore_for_file: unnecessary_getters_setters

import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:protocol_brain/protocol_brain.dart';
import 'package:rain_core/rain_core.dart';

import 'package:rain/infrastructure/notifications/rain_notification_service.dart';
import 'package:rain/infrastructure/diagnostics/tracing/trace_context.dart';
import 'connection_attempt_coordinator.dart';
import 'app_exit_coordinator.dart';
import 'call_media_recovery_policy.dart';
import 'connection_request_runtime.dart';
import 'connection_request_state.dart';
import 'file_transfer_runtime.dart';
import 'file_transfer_progress_batcher.dart';
import 'friend_runtime.dart';
import 'runtime_interaction_guard.dart';
import 'serialized_runtime_mutations.dart';
import 'video_call_renderers.dart';
import 'voice_call_runtime.dart';
import 'voice_call_state.dart';

export 'connection_request_runtime.dart';
export 'file_transfer_runtime.dart';
export 'friend_runtime.dart';
export 'voice_call_runtime.dart';

enum FriendRequestResult { sent, acceptedExisting }

typedef RuntimeErrorRecorder =
    void Function(
      Object error,
      StackTrace? stackTrace, {
      required String source,
      required bool fatal,
      String? flutterLibrary,
      String? flutterContext,
    });

typedef RuntimeEventRecorder =
    void Function({
      required String category,
      required String name,
      String severity,
      String? message,
      Map<String, Object?> context,
    });

String _formatRetryDelay(Duration delay) {
  if (delay.inSeconds <= 1) {
    return '1 second';
  }
  if (delay.inMinutes < 1) {
    return '${delay.inSeconds} seconds';
  }
  if (delay.inMinutes == 1) {
    return '1 minute';
  }
  return '${delay.inMinutes} minutes';
}

const int peerPresenceFreshnessWindowMs = 30000;
const Duration peerPresenceFreshnessWindow = Duration(
  milliseconds: peerPresenceFreshnessWindowMs,
);
const Duration _peerPresenceFreshnessWindow = peerPresenceFreshnessWindow;

bool backendIdentityIsFreshlyOnline(
  BackendIdentity identity, {
  int? nowMs,
  int freshnessWindowMs = peerPresenceFreshnessWindowMs,
}) {
  final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
  final presenceAgeMs = identity.lastHeartbeat <= 0
      ? null
      : now - identity.lastHeartbeat;
  final normalizedState = identity.presenceState?.trim().toLowerCase();
  final stateAllowsOnline =
      normalizedState == null ||
      normalizedState.isEmpty ||
      normalizedState == 'online';
  return identity.online &&
      stateAllowsOnline &&
      presenceAgeMs != null &&
      presenceAgeMs < freshnessWindowMs;
}

final class RuntimePeerPresenceSnapshot {
  const RuntimePeerPresenceSnapshot({
    required this.peerId,
    required this.online,
    required this.rawOnline,
    required this.observedAtMs,
    this.lastHeartbeat,
    this.lastSeen,
    this.presenceAgeMs,
    this.freshnessWindowMs = peerPresenceFreshnessWindowMs,
    this.presenceSessionId,
    this.presenceStartedAt,
    this.presenceState,
  });

  final String peerId;
  final bool online;
  final bool rawOnline;
  final int observedAtMs;
  final int? lastHeartbeat;
  final int? lastSeen;
  final int? presenceAgeMs;
  final int freshnessWindowMs;
  final String? presenceSessionId;
  final int? presenceStartedAt;
  final String? presenceState;

  factory RuntimePeerPresenceSnapshot._fromResolved({
    required String peerId,
    required ResolvedBackendPresence presence,
    required int observedAtMs,
  }) {
    return RuntimePeerPresenceSnapshot(
      peerId: peerId,
      online: presence.online,
      rawOnline: presence.rawOnline,
      observedAtMs: observedAtMs,
      lastHeartbeat: presence.lastHeartbeat,
      lastSeen: presence.lastSeen,
      presenceAgeMs: presence.presenceAgeMs,
      freshnessWindowMs: presence.freshnessWindowMs,
      presenceSessionId: presence.sessionId,
      presenceStartedAt: presence.startedAt,
      presenceState: presence.state,
    );
  }

  factory RuntimePeerPresenceSnapshot.fromPresenceStream({
    required String peerId,
    required bool online,
    required int observedAtMs,
    RuntimePeerPresenceSnapshot? previous,
  }) {
    return RuntimePeerPresenceSnapshot(
      peerId: peerId,
      online: online,
      rawOnline: online,
      observedAtMs: observedAtMs,
      lastHeartbeat: online ? observedAtMs : previous?.lastHeartbeat,
      lastSeen: online ? observedAtMs : previous?.lastSeen,
      presenceAgeMs: online ? 0 : previous?.presenceAgeMs,
      freshnessWindowMs:
          previous?.freshnessWindowMs ?? peerPresenceFreshnessWindowMs,
      presenceSessionId: previous?.presenceSessionId,
      presenceStartedAt: previous?.presenceStartedAt,
      presenceState: online ? 'online' : 'offline',
    );
  }
}

final class ResolvedBackendPresence {
  const ResolvedBackendPresence({
    required this.online,
    required this.rawOnline,
    required this.lastHeartbeat,
    required this.lastSeen,
    required this.presenceAgeMs,
    required this.freshnessWindowMs,
    required this.sessionId,
    required this.startedAt,
    required this.state,
  });

  final bool online;
  final bool rawOnline;
  final int lastHeartbeat;
  final int lastSeen;
  final int? presenceAgeMs;
  final int freshnessWindowMs;
  final String? sessionId;
  final int? startedAt;
  final String? state;

  bool get staleRawOnline => rawOnline && !online;

  Map<String, Object?> toDiagnostics() {
    return <String, Object?>{
      'presenceSource': 'backend',
      'rawOnline': rawOnline,
      'resolvedOnline': online,
      'lastHeartbeat': lastHeartbeat,
      'lastSeen': lastSeen,
      'presenceAgeMs': presenceAgeMs,
      'freshnessWindowMs': freshnessWindowMs,
      'presenceSessionId': sessionId,
      'presenceStartedAt': startedAt,
      'presenceState': state,
      'staleRawOnline': staleRawOnline,
    };
  }
}

class RainRuntimeController with WidgetsBindingObserver {
  static const Duration _dataEventNotifyThrottleWindow = Duration(
    milliseconds: 250,
  );

  RainRuntimeController({
    required this.selfIdentity,
    this.sessionGeneration = 0,
    required this.adapter,
    required this.brain,
    required this.database,
    required this.friendStore,
    required this.messageStore,
    required this.offlineQueueStore,
    required this.messageDeliveryService,
    FileTransferStore? fileTransferStore,
    VoiceSignalingAdapter? voiceSignalingAdapter,
    SignalingCipher? voiceSignalingCipher,
    ConnectionRequestAdapter? connectionRequestAdapter,
    this.connectionRequestNotificationService,
    this.heartbeatInterval = const Duration(seconds: 10),
    this.friendRequestRefreshInterval = Duration.zero,
    this.maxPassivePeerListeners = 32,
    this.networkRecoveryDebounce = const Duration(seconds: 2),
    Duration initialConnectionRetryBackoff = const Duration(seconds: 3),
    Duration maxConnectionRetryBackoff = const Duration(minutes: 1),
    Future<Directory> Function()? documentsDirectoryProvider,
    this.startupMediaPermissionWarmup,
    this.videoCallRendererFactory = const RtcVideoCallRendererFactory(),
    this.videoCallRemoteFirstFrameTimeout = const Duration(seconds: 8),
    this.callMediaRecoveryPolicy = const CallMediaRecoveryPolicy(),
    Duration? activeCallReconnectGrace,
    this.fileTransferBufferPollInterval = fileTransferBackpressurePollInterval,
    this.fileTransferBufferTimeout = fileTransferBackpressureTimeout,
    this.errorRecorder,
    this.eventRecorder,
  }) : assert(fileTransferBufferPollInterval > Duration.zero),
       assert(fileTransferBufferTimeout > Duration.zero),
       fileTransferStore = fileTransferStore ?? FileTransferStore(database),
       activeCallReconnectGrace =
           activeCallReconnectGrace ??
           callMediaRecoveryPolicy.disconnectedGrace,
       voiceSignalingAdapter =
           voiceSignalingAdapter ??
           (adapter is VoiceSignalingAdapter
               ? adapter as VoiceSignalingAdapter
               : null),
       connectionRequestAdapter =
           connectionRequestAdapter ??
           (adapter is ConnectionRequestAdapter
               ? adapter as ConnectionRequestAdapter
               : null),
       voiceSignalingCipher =
           voiceSignalingCipher ??
           SignalingCipher.fromKeyMaterial(
             'test-key-not-for-production-use-0123456789',
           ),
       _documentsDirectoryProvider =
           documentsDirectoryProvider ?? getApplicationDocumentsDirectory,
       _connectionCoordinator = ConnectionAttemptCoordinator(
         passiveListenerLimit: maxPassivePeerListeners,
         networkRecoveryDebounce: networkRecoveryDebounce,
         initialRetryBackoff: initialConnectionRetryBackoff,
         maxRetryBackoff: maxConnectionRetryBackoff,
       ) {
    _fileProgressBatcher = FileTransferProgressBatcher(
      markProgress: this.fileTransferStore.markProgress,
    );
  }

  final RainIdentity selfIdentity;
  final int sessionGeneration;
  final SignalingAdapter adapter;
  final SessionManager? brain;
  final RainDatabase database;
  final FriendStore friendStore;
  final MessageStore messageStore;
  final OfflineQueueStore offlineQueueStore;
  final MessageDeliveryService messageDeliveryService;
  final FileTransferStore fileTransferStore;
  final VoiceSignalingAdapter? voiceSignalingAdapter;
  final ConnectionRequestAdapter? connectionRequestAdapter;
  final RainNotificationService? connectionRequestNotificationService;
  final SignalingCipher voiceSignalingCipher;
  final Duration heartbeatInterval;
  final Duration friendRequestRefreshInterval;
  final int maxPassivePeerListeners;
  final Duration networkRecoveryDebounce;
  final RuntimeErrorRecorder? errorRecorder;
  final RuntimeEventRecorder? eventRecorder;
  final Future<Directory> Function() _documentsDirectoryProvider;
  final Future<void> Function()? startupMediaPermissionWarmup;
  final VideoCallRendererFactory videoCallRendererFactory;
  final Duration videoCallRemoteFirstFrameTimeout;
  final CallMediaRecoveryPolicy callMediaRecoveryPolicy;
  final Duration activeCallReconnectGrace;
  final Duration fileTransferBufferPollInterval;
  final Duration fileTransferBufferTimeout;
  final Set<String> _manualDisconnectedPeers = <String>{};
  final Set<String> _recoverableDisconnectedPeers = <String>{};
  final Map<String, int> _lastDataEventTimestamps = <String, int>{};
  final Map<String, RuntimePeerPresenceSnapshot> _peerPresenceSnapshots =
      <String, RuntimePeerPresenceSnapshot>{};
  final Set<String> _registeredPeerListeners = <String>{};
  final Set<String> _passivePeerListeners = <String>{};
  final Set<String> _unblockingPeers = <String>{};
  final Map<String, StreamSubscription<bool>> _presenceSubscriptions =
      <String, StreamSubscription<bool>>{};
  final Map<String, PeerDisconnectIntent> _pendingPeerDisconnectIntents =
      <String, PeerDisconnectIntent>{};
  final Map<String, FileTransferFrame> _pendingFileChunks =
      <String, FileTransferFrame>{};
  final Map<String, int> _receiveProgressOffsets = <String, int>{};
  final Map<String, FileTransferFlushPolicy> _receiveFlushPolicies =
      <String, FileTransferFlushPolicy>{};
  final Map<String, IOSink> _receiveFileSinks = <String, IOSink>{};
  final Map<String, String> _receiveFileSinkPaths = <String, String>{};
  final Map<String, Future<void>> _fileMessageQueues = <String, Future<void>>{};
  final Map<String, OutgoingFileSource> _outgoingFileSources =
      <String, OutgoingFileSource>{};
  final Map<String, String> _outgoingFileHashes = <String, String>{};
  final Set<String> _canceledTransfers = <String>{};
  final Map<String, FileTransferRecord> _incomingTransferRecordCache =
      <String, FileTransferRecord>{};
  final StreamController<VoiceCallState> _voiceCallStateController =
      StreamController<VoiceCallState>.broadcast();
  final StreamController<void> _peerConnectivityChangeController =
      StreamController<void>.broadcast();
  VoiceCallState _voiceCallState = const VoiceCallState.idle();
  VoiceCallSession? _voiceCallSession;
  String? _acceptingVoiceCallId;
  String? _endingCallPeerId;
  StreamSubscription<VoiceCallSessionState>? _voiceCallSessionSubscription;
  Timer? _voiceCallReconnectGraceTimer;
  final Set<String> _terminalVoiceCallSessionKeys = <String>{};
  final Map<String, List<String>> _voiceRoomStatusTimelineByCall =
      <String, List<String>>{};
  final Map<String, VoiceCallSignalingStatus> _voiceRoomSignalingStatusByCall =
      <String, VoiceCallSignalingStatus>{};
  IceCandidateBatcher<VoiceSignalingEnvelope>? _voiceIceCandidateBatcher;
  int _voiceLocalIceCandidateCount = 0;
  CallMediaConnection? _videoCallMediaConnection;
  VideoCallRenderers? _videoCallRenderers;
  VideoCallRendererState? _lastVideoCallRendererState;
  String? _handledVideoFirstFrameTimeoutCallId;
  String? _lastLoggedVoiceCallStateSignature;
  String? _lastLoggedPeerUiSplitSignature;
  String? _lastLoggedVideoRendererSignature;
  StreamSubscription<VideoCallRendererState>? _videoCallRendererSubscription;
  final List<StreamSubscription<dynamic>> _voiceSignalingSubscriptions =
      <StreamSubscription<dynamic>>[];
  final List<StreamSubscription<dynamic>> _connectionRequestSubscriptions =
      <StreamSubscription<dynamic>>[];
  final Set<String> _activeConnectionRequestNotificationIds = <String>{};
  final Set<String> _connectionRequestNotificationFallbackKeys = <String>{};
  final Map<String, List<int>> _connectionRequestSendHistoryByPeer =
      <String, List<int>>{};
  final Map<String, int> _connectionRequestCooldownUntilByPeer =
      <String, int>{};
  final StreamController<ConnectionRequestState>
  _connectionRequestStateController =
      StreamController<ConnectionRequestState>.broadcast();
  ConnectionRequestState _connectionRequestState =
      const ConnectionRequestState.idle();
  late final FileTransferProgressBatcher _fileProgressBatcher;
  final ConnectionAttemptCoordinator _connectionCoordinator;

  final List<StreamSubscription<dynamic>> _subscriptions =
      <StreamSubscription<dynamic>>[];
  Timer? _heartbeatTimer;
  Timer? _friendRequestRefreshTimer;
  Timer? _backgroundOfflineTimer;
  Timer? _dataEventNotifyThrottleTimer;
  bool _presenceHeartbeatPaused = false;
  bool _started = false;
  bool _shutDown = false;
  Future<void>? _shutdownFuture;
  final SerializedRuntimeMutations _localMutations =
      SerializedRuntimeMutations();

  String _normalizedUsername(String username) {
    return username.trim().toLowerCase();
  }

  // Internal accessors used by imported runtime extension libraries.
  Future<Directory> Function() get documentsDirectoryProvider =>
      _documentsDirectoryProvider;
  SerializedRuntimeMutations get localMutations => _localMutations;
  Set<String> get mutableManualDisconnectedPeers => _manualDisconnectedPeers;
  Set<String> get recoverableDisconnectedPeers => _recoverableDisconnectedPeers;
  Map<String, RuntimePeerPresenceSnapshot> get peerPresenceSnapshotCache =>
      _peerPresenceSnapshots;
  Set<String> get registeredPeerListeners => _registeredPeerListeners;
  Set<String> get passivePeerListeners => _passivePeerListeners;
  Set<String> get unblockingPeers => _unblockingPeers;
  Map<String, StreamSubscription<bool>> get presenceSubscriptions =>
      _presenceSubscriptions;
  Map<String, FileTransferFrame> get pendingFileChunks => _pendingFileChunks;
  Map<String, int> get receiveProgressOffsets => _receiveProgressOffsets;
  Map<String, FileTransferFlushPolicy> get receiveFlushPolicies =>
      _receiveFlushPolicies;
  Map<String, IOSink> get receiveFileSinks => _receiveFileSinks;
  Map<String, String> get receiveFileSinkPaths => _receiveFileSinkPaths;
  Map<String, Future<void>> get fileMessageQueues => _fileMessageQueues;
  Map<String, OutgoingFileSource> get outgoingFileSources =>
      _outgoingFileSources;
  Map<String, String> get outgoingFileHashes => _outgoingFileHashes;
  Set<String> get canceledTransfers => _canceledTransfers;
  Map<String, FileTransferRecord> get incomingTransferRecordCache =>
      _incomingTransferRecordCache;
  FileTransferProgressBatcher get fileProgressBatcher => _fileProgressBatcher;
  StreamController<VoiceCallState> get voiceCallStateController =>
      _voiceCallStateController;
  VoiceCallSession? get voiceCallSession => _voiceCallSession;
  set voiceCallSession(VoiceCallSession? value) => _voiceCallSession = value;
  String? get acceptingVoiceCallId => _acceptingVoiceCallId;
  set acceptingVoiceCallId(String? value) => _acceptingVoiceCallId = value;
  String? get endingCallPeerId => _endingCallPeerId;
  set endingCallPeerId(String? value) => _endingCallPeerId = value;
  StreamSubscription<VoiceCallSessionState>? get voiceCallSessionSubscription =>
      _voiceCallSessionSubscription;
  set voiceCallSessionSubscription(
    StreamSubscription<VoiceCallSessionState>? value,
  ) => _voiceCallSessionSubscription = value;
  Timer? get voiceCallReconnectGraceTimer => _voiceCallReconnectGraceTimer;
  set voiceCallReconnectGraceTimer(Timer? value) =>
      _voiceCallReconnectGraceTimer = value;
  Set<String> get terminalVoiceCallSessionKeys => _terminalVoiceCallSessionKeys;
  Map<String, List<String>> get voiceRoomStatusTimelineByCall =>
      _voiceRoomStatusTimelineByCall;
  Map<String, VoiceCallSignalingStatus> get voiceRoomSignalingStatusByCall =>
      _voiceRoomSignalingStatusByCall;
  IceCandidateBatcher<VoiceSignalingEnvelope>? get voiceIceCandidateBatcher =>
      _voiceIceCandidateBatcher;
  set voiceIceCandidateBatcher(
    IceCandidateBatcher<VoiceSignalingEnvelope>? value,
  ) => _voiceIceCandidateBatcher = value;
  int get voiceLocalIceCandidateCount => _voiceLocalIceCandidateCount;
  set voiceLocalIceCandidateCount(int value) =>
      _voiceLocalIceCandidateCount = value;
  CallMediaConnection? get videoCallMediaConnection =>
      _videoCallMediaConnection;
  set videoCallMediaConnection(CallMediaConnection? value) =>
      _videoCallMediaConnection = value;
  VideoCallRendererState? get lastVideoCallRendererState =>
      _lastVideoCallRendererState;
  set lastVideoCallRendererState(VideoCallRendererState? value) =>
      _lastVideoCallRendererState = value;
  String? get handledVideoFirstFrameTimeoutCallId =>
      _handledVideoFirstFrameTimeoutCallId;
  set handledVideoFirstFrameTimeoutCallId(String? value) =>
      _handledVideoFirstFrameTimeoutCallId = value;
  String? get lastLoggedVoiceCallStateSignature =>
      _lastLoggedVoiceCallStateSignature;
  set lastLoggedVoiceCallStateSignature(String? value) =>
      _lastLoggedVoiceCallStateSignature = value;
  String? get lastLoggedPeerUiSplitSignature => _lastLoggedPeerUiSplitSignature;
  set lastLoggedPeerUiSplitSignature(String? value) =>
      _lastLoggedPeerUiSplitSignature = value;
  String? get lastLoggedVideoRendererSignature =>
      _lastLoggedVideoRendererSignature;
  set lastLoggedVideoRendererSignature(String? value) =>
      _lastLoggedVideoRendererSignature = value;
  StreamSubscription<VideoCallRendererState>?
  get videoCallRendererSubscription => _videoCallRendererSubscription;
  set videoCallRendererSubscription(
    StreamSubscription<VideoCallRendererState>? value,
  ) => _videoCallRendererSubscription = value;
  List<StreamSubscription<dynamic>> get voiceSignalingSubscriptions =>
      _voiceSignalingSubscriptions;
  List<StreamSubscription<dynamic>> get connectionRequestSubscriptions =>
      _connectionRequestSubscriptions;
  Set<String> get activeConnectionRequestNotificationIds =>
      _activeConnectionRequestNotificationIds;
  Set<String> get connectionRequestNotificationFallbackKeys =>
      _connectionRequestNotificationFallbackKeys;
  Map<String, List<int>> get connectionRequestSendHistoryByPeer =>
      _connectionRequestSendHistoryByPeer;
  Map<String, int> get connectionRequestCooldownUntilByPeer =>
      _connectionRequestCooldownUntilByPeer;
  StreamController<ConnectionRequestState>
  get connectionRequestStateController => _connectionRequestStateController;
  ConnectionAttemptCoordinator get connectionCoordinator =>
      _connectionCoordinator;
  bool get runtimeStarted => _started;
  bool get runtimeShutDown => _shutDown;

  String normalizeUsername(String username) => _normalizedUsername(username);

  void notifyPeerConnectivityChanged() => _notifyPeerConnectivityChanged();

  void cacheResolvedPeerPresence(
    String username,
    ResolvedBackendPresence presence, {
    int? observedAtMs,
  }) {
    _cacheResolvedPeerPresence(username, presence, observedAtMs: observedAtMs);
  }

  void cachePresenceStreamValue(String username, bool isOnline) {
    _cachePresenceStreamValue(username, isOnline);
  }

  ResolvedBackendPresence resolveBackendPresence(
    BackendIdentity identity, {
    int? nowMs,
  }) {
    return _resolveBackendPresence(identity, nowMs: nowMs);
  }

  Future<ResolvedBackendPresence?> fetchPeerPresenceSnapshot(
    String username, {
    required String action,
    bool updateLocalPresence = true,
  }) {
    return _fetchPeerPresenceSnapshot(
      username,
      action: action,
      updateLocalPresence: updateLocalPresence,
    );
  }

  RainGender? backendGender(String? value) => _backendGender(value);

  void recordRuntimeEvent({
    required String category,
    required String name,
    String severity = 'info',
    String? message,
    Map<String, Object?> context = const <String, Object?>{},
  }) {
    _recordRuntimeEvent(
      category: category,
      name: name,
      severity: severity,
      message: message,
      context: context,
    );
  }

  Future<void> disconnectBrainPeer(String peerId, PeerDisconnectIntent intent) {
    return _disconnectBrainPeer(peerId, intent);
  }

  Set<String> get manualDisconnectedPeers =>
      Set<String>.unmodifiable(_manualDisconnectedPeers);

  Map<String, int> get lastDataEventTimestamps =>
      Map<String, int>.unmodifiable(_lastDataEventTimestamps);

  Map<String, RuntimePeerPresenceSnapshot> get peerPresenceSnapshots =>
      Map<String, RuntimePeerPresenceSnapshot>.unmodifiable(
        _peerPresenceSnapshots,
      );

  Stream<void> watchPeerConnectivityChanges() async* {
    yield null;
    yield* _peerConnectivityChangeController.stream;
  }

  void _notifyPeerConnectivityChanged() {
    if (!_peerConnectivityChangeController.isClosed) {
      _peerConnectivityChangeController.add(null);
    }
  }

  void _recordDataEvent(String peerId, int timestamp) {
    final normalizedPeerId = _normalizedUsername(peerId);
    final previous = _lastDataEventTimestamps[normalizedPeerId];
    if (previous != null && previous >= timestamp) {
      return;
    }
    _lastDataEventTimestamps[normalizedPeerId] = timestamp;
    // Leading-edge throttle: data bursts (file chunks) would otherwise rebuild
    // peer snapshots per 32 KiB chunk. First event notifies immediately; the
    // trailing edge flushes the newest recorded timestamp once per window.
    if (_dataEventNotifyThrottleTimer != null) {
      return;
    }
    _notifyPeerConnectivityChanged();
    _dataEventNotifyThrottleTimer = Timer(_dataEventNotifyThrottleWindow, () {
      _dataEventNotifyThrottleTimer = null;
      _notifyPeerConnectivityChanged();
    });
  }

  void _cacheResolvedPeerPresence(
    String username,
    ResolvedBackendPresence presence, {
    int? observedAtMs,
  }) {
    final normalizedUsername = _normalizedUsername(username);
    _peerPresenceSnapshots[normalizedUsername] =
        RuntimePeerPresenceSnapshot._fromResolved(
          peerId: normalizedUsername,
          presence: presence,
          observedAtMs: observedAtMs ?? DateTime.now().millisecondsSinceEpoch,
        );
    _notifyPeerConnectivityChanged();
  }

  void _cachePresenceStreamValue(String username, bool isOnline) {
    final normalizedUsername = _normalizedUsername(username);
    final observedAtMs = DateTime.now().millisecondsSinceEpoch;
    _peerPresenceSnapshots[normalizedUsername] =
        RuntimePeerPresenceSnapshot.fromPresenceStream(
          peerId: normalizedUsername,
          online: isOnline,
          observedAtMs: observedAtMs,
          previous: _peerPresenceSnapshots[normalizedUsername],
        );
    _notifyPeerConnectivityChanged();
  }

  ResolvedBackendPresence _resolveBackendPresence(
    BackendIdentity identity, {
    int? nowMs,
  }) {
    final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    final presenceAgeMs = identity.lastHeartbeat <= 0
        ? null
        : now - identity.lastHeartbeat;
    final normalizedState = identity.presenceState?.trim().toLowerCase();
    final online = backendIdentityIsFreshlyOnline(identity, nowMs: now);
    return ResolvedBackendPresence(
      online: online,
      rawOnline: identity.online,
      lastHeartbeat: identity.lastHeartbeat,
      lastSeen: identity.lastSeen,
      presenceAgeMs: presenceAgeMs,
      freshnessWindowMs: _peerPresenceFreshnessWindow.inMilliseconds,
      sessionId: identity.presenceSessionId,
      startedAt: identity.presenceStartedAt,
      state: normalizedState,
    );
  }

  Future<ResolvedBackendPresence?> _fetchPeerPresenceSnapshot(
    String username, {
    required String action,
    bool updateLocalPresence = true,
  }) async {
    final trace = TraceContext.create();
    return TraceContext.runAsync(trace, () async {
      final normalizedUsername = _normalizedUsername(username);
      final backendIdentity = await adapter.fetchIdentity(normalizedUsername);
      if (backendIdentity == null) {
        return null;
      }
      final presence = _resolveBackendPresence(backendIdentity);
      _cacheResolvedPeerPresence(normalizedUsername, presence);
      if (updateLocalPresence) {
        await _localMutations.run(
          () => friendStore.updatePresence(normalizedUsername, presence.online),
        );
      }
      if (presence.staleRawOnline) {
        _recordRuntimeEvent(
          category: 'presence',
          name: 'backend_presence_stale_resolved_offline',
          severity: 'warning',
          message: 'Backend presence heartbeat is stale.',
          context: <String, Object?>{
            'peerId': normalizedUsername,
            'action': action,
            ...presence.toDiagnostics(),
            ...trace.toContext(),
          },
        );
      }
      return presence;
    });
  }

  Future<bool?> isPeerFreshlyOnline(
    String username, {
    String action = 'presence_check',
  }) async {
    final presence = await _fetchPeerPresenceSnapshot(username, action: action);
    return presence?.online;
  }

  ConnectionCoordinatorSnapshot connectionCoordinatorSnapshotFor(
    String username,
  ) {
    return _connectionCoordinator.snapshot(
      peerId: _normalizedUsername(username),
    );
  }

  VoiceCallState get voiceCallState => _voiceCallState;
  set voiceCallState(VoiceCallState value) => _voiceCallState = value;

  ConnectionRequestState get connectionRequestState => _connectionRequestState;
  set connectionRequestState(ConnectionRequestState value) =>
      _connectionRequestState = value;

  VideoCallRenderers? get videoCallRenderers => _videoCallRenderers;
  set videoCallRenderers(VideoCallRenderers? value) =>
      _videoCallRenderers = value;

  Future<void> refreshCallMediaProcessingConfig() async {
    final media = _videoCallMediaConnection;
    if (media == null) {
      return;
    }
    await media.refreshProcessingConfig();
    _recordRuntimeEvent(
      category: 'call',
      name: 'media_processing_config_refreshed',
      context: <String, Object?>{
        'callId': _voiceCallState.callId,
        'peerId': _voiceCallState.peerId,
        'mediaMode': _voiceCallState.mediaMode.name,
      },
    );
  }

  Stream<VoiceCallState> watchVoiceCallState() async* {
    yield _voiceCallState;
    yield* _voiceCallStateController.stream;
  }

  RainGender? _backendGender(String? value) {
    final normalized = value?.trim().toLowerCase();
    if (normalized == null || normalized.isEmpty) {
      return null;
    }
    for (final gender in RainGender.values) {
      if (gender.name == normalized) {
        return gender;
      }
    }
    return null;
  }

  Future<void> start() async {
    if (_started) {
      return;
    }
    _started = true;
    _recordRuntimeEvent(category: 'runtime', name: 'start_requested');
    WidgetsBinding.instance.addObserver(this);

    try {
      await adapter.ensureSignedInAs(selfIdentity.username);
      final currentUid = await adapter.currentUid();
      final now = DateTime.now().millisecondsSinceEpoch;
      await adapter.upsertIdentity(
        BackendIdentity(
          username: selfIdentity.username,
          uid: currentUid,
          displayName: selfIdentity.displayName,
          gender: selfIdentity.gender?.name,
          registeredAt: selfIdentity.createdAt,
          lastSeen: now,
          lastHeartbeat: now,
          online: true,
        ),
      );
      await adapter.setPresence(selfIdentity.username, true);
    } on SignalingSessionExpiredException {
      rethrow;
    } on Object catch (error, stackTrace) {
      Error.throwWithStackTrace(
        StateError('Could not authenticate signaling backend: $error'),
        stackTrace,
      );
    }
    await _localMutations.run(offlineQueueStore.recoverInFlightMessages);
    await syncRelationships();
    await _warmUpStartupMediaPermissions();
    final existingFriends = await friendStore.loadFriends();
    await startConnectionRequestRuntime();
    _recordRuntimeEvent(
      category: 'runtime',
      name: 'started',
      context: <String, Object?>{
        'acceptedFriendCount': existingFriends.length,
        'hasBrain': brain != null,
      },
    );

    for (final friend in existingFriends) {
      if (!isBlockedState(friend.state)) {
        watchPresence(friend.username);
      }
    }
    await reconcilePassivePeerListeners(existingFriends);

    if (friendRequestRefreshInterval > Duration.zero) {
      _friendRequestRefreshTimer = Timer.periodic(
        friendRequestRefreshInterval,
        (_) => refreshRelationshipsSilently(),
      );
    }

    _heartbeatTimer = Timer.periodic(heartbeatInterval, (_) {
      unawaited(_sendHeartbeatSafely(reason: 'timer'));
    });

    _subscriptions.add(
      adapter
          .onFriendRequest(selfIdentity.username)
          .listen(
            (String from) async {
              await processIncomingFriendRequest(from);
            },
            onError: (Object error, StackTrace stackTrace) {
              refreshRelationshipsSilently();
            },
          ),
    );

    _subscriptions.add(
      adapter
          .onRelationshipChanged(selfIdentity.username)
          .listen(
            (String username) {
              final normalizedUsername = _normalizedUsername(username);
              if (normalizedUsername.isNotEmpty &&
                  normalizedUsername !=
                      _normalizedUsername(selfIdentity.username)) {
                refreshRelationshipsSilently(onlyUsername: normalizedUsername);
              }
            },
            onError: (Object error, StackTrace stackTrace) {
              refreshRelationshipsSilently();
            },
          ),
    );

    final voiceAdapter = voiceSignalingAdapter;
    if (voiceAdapter != null) {
      unawaited(cleanupStaleVoiceCallArtifacts('startup'));
      _subscriptions.add(
        voiceAdapter
            .watchIncomingCalls(selfIdentity.username)
            .listen(
              (VoiceCallInboxEntry entry) async {
                await handleIncomingVoiceCallEntry(entry);
              },
              onError: (Object error, StackTrace stackTrace) {
                errorRecorder?.call(
                  error,
                  stackTrace,
                  source: 'voice-call-signaling',
                  fatal: false,
                );
              },
            ),
      );
    }

    if (brain != null) {
      _subscriptions.add(
        brain!.onSessionChanged.listen((Session session) {
          _recordRuntimeEvent(
            category: 'connection',
            name: 'session_changed',
            context: _sessionEventContext(session),
          );
          _recordSessionAttemptState(session);
        }),
      );

      _subscriptions.add(
        brain!.onIncomingOfferRejected.listen(
          _connectionCoordinator.recordIncomingOfferRejected,
        ),
      );

      _subscriptions.add(
        brain!.onPeerConnected.listen((Session session) async {
          if (_manualDisconnectedPeers.contains(session.peerId)) {
            _recordRuntimeEvent(
              category: 'connection',
              name: 'peer_connected_ignored_manual_disconnect',
              context: _sessionEventContext(session),
            );
            return;
          }
          _recordRuntimeEvent(
            category: 'connection',
            name: 'peer_connected',
            context: _sessionEventContext(session),
          );
          _recoverableDisconnectedPeers.remove(session.peerId);
          clearVoiceCallReconnectingForPeer(session.peerId);
          _connectionCoordinator.recordAttemptSuccess(session.peerId);
          await _localMutations.run(
            () => messageDeliveryService.flushQueue(
              selfIdentity.username,
              session.peerId,
              sendChat: (String payload) async => session.send(payload),
            ),
          );
        }),
      );

      _subscriptions.add(
        brain!.onPeerDisconnected.listen((String peerId) {
          final pendingIntent = _pendingPeerDisconnectIntents.remove(peerId);
          final recordedIntent =
              pendingIntent ??
              _connectionCoordinator.disconnectIntentFor(peerId);
          _recordRuntimeEvent(
            category: 'connection',
            name: 'peer_disconnected',
            context: <String, Object?>{
              'peerId': peerId,
              'intent': recordedIntent?.name,
              'hadPendingIntent': pendingIntent != null,
            },
          );
          if (recordedIntent == PeerDisconnectIntent.localManual ||
              recordedIntent == PeerDisconnectIntent.localShutdown ||
              recordedIntent == PeerDisconnectIntent.presenceExpired ||
              recordedIntent == PeerDisconnectIntent.transportLost ||
              recordedIntent == PeerDisconnectIntent.networkLost) {
            if (recordedIntent == PeerDisconnectIntent.transportLost ||
                recordedIntent == PeerDisconnectIntent.networkLost) {
              _connectionCoordinator.clearDisconnectIntent(peerId);
            }
            return;
          }
          final session = brain?.getSession(peerId);
          if (session?.state == SessionState.connecting ||
              session?.state == SessionState.reconnecting) {
            _connectionCoordinator.recordDisconnectIntent(
              peerId,
              PeerDisconnectIntent.transportLost,
            );
            markVoiceCallReconnectingForPeer(peerId);
            return;
          }
          _connectionCoordinator.recordDisconnectIntent(
            peerId,
            PeerDisconnectIntent.remoteManual,
          );
          failVoiceCallForPeer(peerId, 'Peer closed Rain. Connection ended.');
          unawaited(
            failActiveTransfersForPeer(
              peerId,
              'Connection lost. Transfer canceled.',
            ),
          );
        }),
      );

      _subscriptions.add(
        brain!.onPeerMessage.listen((SessionMessage message) async {
          final peerId = message.peerId;
          if (peerId == null) {
            return;
          }
          _recordDataEvent(peerId, message.receivedAt.millisecondsSinceEpoch);

          if (message.channel == SessionChannel.control) {
            final text = message.text;
            if (text == null) {
              return;
            }
            final voiceFrame = VoiceCallFrame.tryDecode(text);
            if (voiceFrame != null) {
              await handleVoiceCallFrame(peerId, voiceFrame);
              return;
            }
            await _localMutations.run(
              () => messageDeliveryService.handleControlMessage(text),
            );
            return;
          }

          if (message.channel == SessionChannel.chat) {
            final text = message.text;
            if (text == null) {
              return;
            }
            await _localMutations.run(() async {
              final friend = await friendStore.loadFriend(peerId);
              if (friend?.state != FriendState.friend) {
                return;
              }
              final envelope = MessageEnvelope.fromWireString(text);
              await messageDeliveryService.handleIncomingEnvelope(
                envelope,
                receivedAt: message.receivedAt,
                sendAck: (String rawAck) async {
                  brain!.sendControl(peerId, rawAck);
                },
                onStored: (_) => friendStore.incrementUnread(peerId),
              );
            });
            return;
          }

          if (message.channel == SessionChannel.file) {
            unawaited(enqueueFileChannelMessage(peerId, message));
          }
        }),
      );
    }
  }

  void _recordRuntimeEvent({
    required String category,
    required String name,
    String severity = 'info',
    String? message,
    Map<String, Object?> context = const <String, Object?>{},
  }) {
    final recorder = eventRecorder;
    if (recorder == null) {
      return;
    }
    try {
      recorder(
        category: category,
        name: name,
        severity: severity,
        message: message,
        context: <String, Object?>{
          'self': _normalizedUsername(selfIdentity.username),
          'started': _started,
          'shutDown': _shutDown,
          ...context,
        },
      );
    } catch (_) {
      // Diagnostics must never affect runtime behavior.
    }
  }

  Future<void> _sendHeartbeatSafely({required String reason}) async {
    if (_shutDown || !_started || _presenceHeartbeatPaused) {
      return;
    }
    final trace = TraceContext.create();
    return TraceContext.runAsync(trace, () async {
      try {
        await adapter.sendHeartbeat(selfIdentity.username);
        _recordRuntimeEvent(
          category: 'presence',
          name: 'heartbeat_sent',
          context: <String, Object?>{'reason': reason, ...trace.toContext()},
        );
      } catch (error, stackTrace) {
        _recordRuntimeEvent(
          category: 'presence',
          name: 'heartbeat_failed',
          severity: 'warning',
          message: error.toString(),
          context: <String, Object?>{'reason': reason, ...trace.toContext()},
        );
        errorRecorder?.call(
          error,
          stackTrace,
          source: 'presence-heartbeat',
          fatal: false,
        );
      }
    });
  }

  Future<void> _setPresenceOnlineSafely(String reason) async {
    if (_shutDown || !_started || _presenceHeartbeatPaused) {
      return;
    }
    final trace = TraceContext.create();
    return TraceContext.runAsync(trace, () async {
      try {
        await adapter.setPresence(selfIdentity.username, true);
        _recordRuntimeEvent(
          category: 'presence',
          name: 'presence_marked_online',
          context: <String, Object?>{'reason': reason, ...trace.toContext()},
        );
      } catch (error, stackTrace) {
        _recordRuntimeEvent(
          category: 'presence',
          name: 'presence_online_failed',
          severity: 'warning',
          message: error.toString(),
          context: <String, Object?>{'reason': reason, ...trace.toContext()},
        );
        errorRecorder?.call(
          error,
          stackTrace,
          source: 'presence-online',
          fatal: false,
        );
        return;
      }
      await _sendHeartbeatSafely(reason: '$reason heartbeat');
    });
  }

  Future<void> _setPresenceOfflineSafely(String reason) async {
    if (_shutDown || !_started) {
      return;
    }
    final trace = TraceContext.create();
    return TraceContext.runAsync(trace, () async {
      try {
        await adapter.setPresence(selfIdentity.username, false);
        _recordRuntimeEvent(
          category: 'presence',
          name: 'presence_marked_offline',
          context: <String, Object?>{'reason': reason, ...trace.toContext()},
        );
      } catch (error, stackTrace) {
        _recordRuntimeEvent(
          category: 'presence',
          name: 'presence_offline_failed',
          severity: 'warning',
          message: error.toString(),
          context: <String, Object?>{'reason': reason, ...trace.toContext()},
        );
        errorRecorder?.call(
          error,
          stackTrace,
          source: 'presence-offline',
          fatal: false,
        );
      }
    });
  }

  Map<String, Object?> _sessionEventContext(Session session) {
    final route = session.route;
    return <String, Object?>{
      'peerId': session.peerId,
      'state': session.state.name,
      'phase': session.phase.name,
      'detail': session.detail,
      'error': session.error,
      'retryAttempt': session.retryAttempt,
      'roomId': session.roomId,
      'isOfferOwner': session.isOfferOwner,
      'routeKind': route.kind.name,
      'selectedCandidatePairId': route.selectedCandidatePairId,
      'localCandidateType': route.localCandidateType,
      'remoteCandidateType': route.remoteCandidateType,
      'addressFamily': route.addressFamily.name,
      'protocol': route.protocol,
      'relayProtocol': route.relayProtocol,
      'rtt': route.rtt,
      'bitrate': route.bitrate,
    };
  }

  Future<void> _warmUpStartupMediaPermissions() async {
    final warmup = startupMediaPermissionWarmup;
    if (warmup == null) {
      return;
    }
    try {
      await warmup();
    } catch (error, stackTrace) {
      errorRecorder?.call(
        error,
        stackTrace,
        source: 'media-permission-warmup',
        fatal: false,
      );
    }
  }

  Future<void> acceptFriend(String username) async {
    final normalizedUsername = _normalizedUsername(username);
    // Prefer using an existing displayName if available to preserve
    // the user's chosen display name instead of falling back to the username.
    await syncRelationships(onlyUsername: normalizedUsername);
    final existing = await _localMutations.run(
      () => friendStore.loadFriend(normalizedUsername),
    );
    if (existing?.state != FriendState.pendingIncoming &&
        existing?.state != FriendState.pendingOutgoing &&
        existing?.state != FriendState.friend) {
      throw StateError(
        'There is no pending friend request from @$normalizedUsername.',
      );
    }
    final displayName = existing?.displayName ?? normalizedUsername;
    await adapter.upsertFriendship(selfIdentity.username, normalizedUsername);
    await _localMutations.run(
      () => friendStore.markAccepted(
        normalizedUsername,
        displayName: displayName,
        gender: existing?.gender,
      ),
    );
    await refreshPassivePeerListeners();
  }

  Future<void> blockFriend(String username) async {
    final normalizedUsername = _normalizedUsername(username);
    await failActiveTransfersForPeer(
      normalizedUsername,
      'Transfer canceled because the peer was blocked.',
    );
    await adapter.blockUser(selfIdentity.username, normalizedUsername);
    await clearFriendRequests(normalizedUsername);
    await adapter.deleteFriendship(selfIdentity.username, normalizedUsername);
    await _localMutations.run(() => friendStore.block(normalizedUsername));
    await stopTrackingPeer(normalizedUsername);
  }

  Future<void> unblockFriend(String username) async {
    final normalizedUsername = _normalizedUsername(username);
    _unblockingPeers.add(normalizedUsername);
    try {
      await adapter.unblockUser(selfIdentity.username, normalizedUsername);
      await _localMutations.run(() => friendStore.unblock(normalizedUsername));
      await stopTrackingPeer(normalizedUsername);
    } finally {
      _unblockingPeers.remove(normalizedUsername);
    }
  }

  Future<void> unfriend(String username) async {
    final normalizedUsername = _normalizedUsername(username);
    await failActiveTransfersForPeer(
      normalizedUsername,
      'Transfer canceled because the peer was removed.',
    );
    final existing = await _localMutations.run(
      () => friendStore.loadFriend(normalizedUsername),
    );
    if (existing?.state != FriendState.friend) {
      await rejectFriend(normalizedUsername);
      return;
    }

    await adapter.deleteFriendship(selfIdentity.username, normalizedUsername);
    await _localMutations.run(() => friendStore.reject(normalizedUsername));
    await stopTrackingPeer(normalizedUsername);
  }

  Future<void> connectPeer(
    String username, {
    bool interactive = false,
    bool waitForConnected = false,
    bool allowStalePresence = false,
    bool bypassRetryBackoff = false,
    Duration connectionTimeout = const Duration(seconds: 60),
  }) async {
    final normalizedUsername = _normalizedUsername(username);
    _recordRuntimeEvent(
      category: 'connection',
      name: 'connect_requested',
      context: <String, Object?>{
        'peerId': normalizedUsername,
        'interactive': interactive,
        'waitForConnected': waitForConnected,
        'allowStalePresence': allowStalePresence,
        'bypassRetryBackoff': bypassRetryBackoff,
      },
    );
    if (_shutDown) {
      const message = 'Rain is signing out. Sign in again before connecting.';
      _recordRuntimeEvent(
        category: 'connection',
        name: 'connect_blocked_runtime_unavailable',
        severity: interactive ? 'warning' : 'info',
        message: message,
        context: <String, Object?>{
          'peerId': normalizedUsername,
          'started': _started,
          'shutDown': _shutDown,
        },
      );
      if (interactive) {
        throw StateError(message);
      }
      return;
    }
    final connectDecision = RuntimeInteractionGuard.canConnectPeer(
      peerId: normalizedUsername,
      interactive: interactive,
      manualDisconnectedPeers: _manualDisconnectedPeers,
      peerConnectionAvailable: brain != null,
    );
    if (!connectDecision.allowed) {
      _recordRuntimeEvent(
        category: 'connection',
        name: 'connect_blocked',
        severity: interactive ? 'warning' : 'info',
        message: connectDecision.userMessage,
        context: <String, Object?>{
          'peerId': normalizedUsername,
          'reasonCode': connectDecision.reasonCode.name,
          'blockingPeerId': connectDecision.blockingPeerId,
          'callId': connectDecision.callId,
          'transferId': connectDecision.transferId,
        },
      );
      if (interactive) {
        connectDecision.throwIfDenied();
      }
      return;
    }
    var friend = await _localMutations.run(
      () => friendStore.loadFriend(normalizedUsername),
    );
    if (friend?.state != FriendState.friend) {
      await syncRelationships(onlyUsername: normalizedUsername);
      friend = await _localMutations.run(
        () => friendStore.loadFriend(normalizedUsername),
      );
    }
    if (friend?.state != FriendState.friend) {
      if (interactive) {
        final message = switch (friend?.state) {
          FriendState.pendingOutgoing =>
            'Wait for @$normalizedUsername to accept your friend request before connecting.',
          FriendState.pendingIncoming =>
            'Accept @$normalizedUsername first before trying to connect.',
          FriendState.blocked =>
            'Unblock @$normalizedUsername before trying to connect.',
          FriendState.blockedByPeer =>
            '@$normalizedUsername blocked you. You cannot connect right now.',
          FriendState.friend => null,
          null => 'Could not find @$normalizedUsername in your friends list.',
        };
        if (message != null) {
          _recordRuntimeEvent(
            category: 'connection',
            name: 'connect_blocked_friend_state',
            severity: 'warning',
            message: message,
            context: <String, Object?>{
              'peerId': normalizedUsername,
              'friendState': friend?.state.name,
            },
          );
          throw StateError(message);
        }
      }
      return;
    }
    if (_manualDisconnectedPeers.contains(normalizedUsername)) {
      if (!interactive) {
        _recordRuntimeEvent(
          category: 'connection',
          name: 'connect_skipped_manual_disconnect',
          context: <String, Object?>{'peerId': normalizedUsername},
        );
        return;
      }
      _recordRuntimeEvent(
        category: 'connection',
        name: 'manual_disconnect_cleared',
        context: <String, Object?>{'peerId': normalizedUsername},
      );
      _manualDisconnectedPeers.remove(normalizedUsername);
      _notifyPeerConnectivityChanged();
      _connectionCoordinator.clearDisconnectIntent(normalizedUsername);
      _recoverableDisconnectedPeers.remove(normalizedUsername);
    }
    var current = brain!.getSession(normalizedUsername);
    if (current?.state == SessionState.connected) {
      _recordRuntimeEvent(
        category: 'connection',
        name: 'connect_already_connected',
        context: _sessionEventContext(current!),
      );
      _recoverableDisconnectedPeers.remove(normalizedUsername);
      return;
    }
    if (current?.state == SessionState.connecting ||
        current?.state == SessionState.reconnecting) {
      if (interactive && bypassRetryBackoff) {
        await _disconnectBrainPeer(
          normalizedUsername,
          PeerDisconnectIntent.transportLost,
        );
        current = brain!.getSession(normalizedUsername);
      } else {
        if (waitForConnected) {
          await waitForPeerConnection(
            normalizedUsername,
            timeout: connectionTimeout,
          );
        }
        return;
      }
    }
    if (current?.state == SessionState.connected) {
      return;
    }
    if (current?.state == SessionState.connecting ||
        current?.state == SessionState.reconnecting) {
      if (waitForConnected) {
        await waitForPeerConnection(
          normalizedUsername,
          timeout: connectionTimeout,
        );
      }
      return;
    }
    final presence = await _fetchPeerPresenceSnapshot(
      normalizedUsername,
      action: 'connect',
    );
    final isOnline = presence?.online ?? false;
    if (!isOnline && !allowStalePresence) {
      _recordRuntimeEvent(
        category: 'connection',
        name: 'connect_blocked_offline',
        severity: interactive ? 'warning' : 'info',
        message:
            '@$normalizedUsername is offline. Keep both apps open, then try again.',
        context: <String, Object?>{
          'peerId': normalizedUsername,
          'friendPresence': friend?.isOnline,
          'backendPresence': presence?.online,
          'rawBackendPresence': presence?.rawOnline,
          'presenceAgeMs': presence?.presenceAgeMs,
          'freshnessWindowMs': presence?.freshnessWindowMs,
          'allowStalePresence': allowStalePresence,
        },
      );
      if (interactive) {
        _recordRuntimeEvent(
          category: 'connection_request',
          name: 'connection_request_direct_failed_offline_fallback',
          severity: 'warning',
          message:
              '@$normalizedUsername went offline during direct connect preflight.',
          context: <String, Object?>{
            'peerId': normalizedUsername,
            'friendPresence': friend?.isOnline,
            'backendPresence': presence?.online,
            'rawBackendPresence': presence?.rawOnline,
            'presenceAgeMs': presence?.presenceAgeMs,
          },
        );
        throw StateError(
          '@$normalizedUsername is offline. Keep both apps open, then try again.',
        );
      }
      return;
    }
    if (bypassRetryBackoff) {
      _connectionCoordinator.clearRetry(normalizedUsername);
    } else {
      final retryGate = _connectionCoordinator.retryGate(normalizedUsername);
      if (!retryGate.allowed) {
        _recordRuntimeEvent(
          category: 'connection',
          name: 'connect_blocked_retry_backoff',
          severity: interactive ? 'warning' : 'info',
          message:
              'Connection attempt is cooling down for ${_formatRetryDelay(retryGate.remaining)}.',
          context: <String, Object?>{
            'peerId': normalizedUsername,
            'remainingMs': retryGate.remaining.inMilliseconds,
          },
        );
        if (interactive) {
          throw StateError(
            'Connection to @$normalizedUsername is cooling down after a failed attempt. Try again in ${_formatRetryDelay(retryGate.remaining)}.',
          );
        }
        return;
      }
    }
    await registerPeerListener(normalizedUsername, bestEffort: false);
    _recordRuntimeEvent(
      category: 'connection',
      name: 'connect_signaling_started',
      context: <String, Object?>{'peerId': normalizedUsername},
    );
    await brain!.connect(normalizedUsername);
    _recoverableDisconnectedPeers.remove(normalizedUsername);
    if (waitForConnected) {
      await waitForPeerConnection(
        normalizedUsername,
        timeout: connectionTimeout,
      );
      _recordRuntimeEvent(
        category: 'connection',
        name: 'connect_wait_completed',
        context: <String, Object?>{'peerId': normalizedUsername},
      );
    }
  }

  Future<void> disconnectPeer(String username) async {
    final normalizedUsername = _normalizedUsername(username);
    _recordRuntimeEvent(
      category: 'connection',
      name: 'disconnect_manual_requested',
      context: <String, Object?>{'peerId': normalizedUsername},
    );
    _manualDisconnectedPeers.add(normalizedUsername);
    _notifyPeerConnectivityChanged();
    _recoverableDisconnectedPeers.remove(normalizedUsername);
    _connectionCoordinator.recordDisconnectIntent(
      normalizedUsername,
      PeerDisconnectIntent.localManual,
    );
    _connectionCoordinator.clearRetry(normalizedUsername);
    await failActiveTransfersForPeer(
      normalizedUsername,
      'Transfer canceled because the peer link was disconnected.',
    );
    await _disconnectBrainPeer(
      normalizedUsername,
      PeerDisconnectIntent.localManual,
    );
    await unregisterPeerListener(normalizedUsername);
    _recordRuntimeEvent(
      category: 'connection',
      name: 'disconnect_manual_completed',
      context: <String, Object?>{'peerId': normalizedUsername},
    );
  }

  Future<void> handleNetworkLost(String reason) async {
    if (_shutDown) {
      return;
    }
    _recordRuntimeEvent(
      category: 'connection',
      name: 'network_lost',
      severity: 'warning',
      message: reason,
    );

    List<FileTransferRecord> activeTransfers;
    try {
      activeTransfers = await fileTransferStore.loadActiveTransfers();
    } catch (_) {
      activeTransfers = const <FileTransferRecord>[];
    }
    for (final transfer in activeTransfers) {
      try {
        await markTransferFailed(transfer.id, reason);
      } catch (_) {
        // Network-loss cleanup is best effort; the next launch can retry cleanup.
      }
    }

    final activeVoicePeer = _voiceCallState.peerId;
    if (_voiceCallState.hasCall && activeVoicePeer != null) {
      await endVoiceCallForPeer(
        activeVoicePeer,
        notifyPeer: false,
        detail: reason,
        failureReason: VoiceCallFailureReason.networkLost,
        failureDetail: 'Network connection lost. Call ended.',
      );
    }

    final sessions = brain?.getSessions() ?? const <Session>[];
    for (final session in sessions) {
      if (!_manualDisconnectedPeers.contains(session.peerId)) {
        _recoverableDisconnectedPeers.add(session.peerId);
      }
      _connectionCoordinator.recordDisconnectIntent(
        session.peerId,
        PeerDisconnectIntent.networkLost,
      );
      await endVoiceCallForPeer(
        session.peerId,
        notifyPeer: false,
        detail: reason,
        failureReason: VoiceCallFailureReason.networkLost,
        failureDetail: 'Network connection lost. Call ended.',
      );
      try {
        await _disconnectBrainPeer(
          session.peerId,
          PeerDisconnectIntent.networkLost,
        );
        await unregisterPeerListener(session.peerId);
      } catch (_) {
        // The network is already unavailable; stale peer cleanup is best effort.
      }
    }
    for (final peerId in _registeredPeerListeners.toList()) {
      try {
        await unregisterPeerListener(peerId);
      } catch (_) {
        // The network is already unavailable; stale listener cleanup is best effort.
      }
    }

    _pendingFileChunks.clear();
    _fileMessageQueues.clear();
    _outgoingFileSources.clear();
    _incomingTransferRecordCache.clear();
    _receiveFlushPolicies.clear();
    await closeAllReceiveSinks(reason: 'network_lost');
  }

  Future<void> _disconnectBrainPeer(
    String peerId,
    PeerDisconnectIntent intent,
  ) async {
    final manager = brain;
    if (manager == null) {
      return;
    }
    _pendingPeerDisconnectIntents[peerId] = intent;
    _connectionCoordinator.recordDisconnectIntent(peerId, intent);
    _recordRuntimeEvent(
      category: 'connection',
      name: 'brain_disconnect_requested',
      context: <String, Object?>{'peerId': peerId, 'intent': intent.name},
    );
    await manager.disconnect(peerId);
  }

  Future<void> handleNetworkAvailable(String reason) async {
    if (_shutDown || !_started) {
      return;
    }
    _recordRuntimeEvent(
      category: 'connection',
      name: 'network_available',
      message: reason,
      context: <String, Object?>{
        'recoverablePeerCount': _recoverableDisconnectedPeers.length,
      },
    );

    await _setPresenceOnlineSafely('network_available');

    await safeSyncRelationships();
    await _connectionCoordinator.scheduleNetworkRecovery(reason, (
      String recoveryReason,
    ) async {
      await brain?.recoverConnections(reason: recoveryReason);
      for (final peerId in _recoverableDisconnectedPeers.toList()) {
        final recoveryDecision = RuntimeInteractionGuard.canAutoRecoverPeer(
          peerId: peerId,
          manualDisconnectedPeers: _manualDisconnectedPeers,
        );
        if (!recoveryDecision.allowed) {
          _recordRuntimeEvent(
            category: 'connection',
            name: 'auto_recovery_blocked',
            context: <String, Object?>{
              'peerId': peerId,
              'reasonCode': recoveryDecision.reasonCode.name,
              'blockingPeerId': recoveryDecision.blockingPeerId,
            },
          );
          continue;
        }
        try {
          final presence = await _fetchPeerPresenceSnapshot(
            peerId,
            action: 'auto_recovery',
          );
          if (presence?.online != true) {
            _recoverableDisconnectedPeers.remove(peerId);
            _connectionCoordinator.recordDisconnectIntent(
              peerId,
              PeerDisconnectIntent.presenceExpired,
            );
            _recordRuntimeEvent(
              category: 'connection',
              name: 'auto_recovery_blocked_stale_presence',
              severity: 'warning',
              message: 'Peer is not freshly online; skipping recovery.',
              context: <String, Object?>{
                'peerId': peerId,
                'presenceKnown': presence != null,
                if (presence != null) ...presence.toDiagnostics(),
              },
            );
            continue;
          }
          final confirmedPresence = presence!;
          _recordRuntimeEvent(
            category: 'connection',
            name: 'auto_recovery_started',
            context: <String, Object?>{
              'peerId': peerId,
              ...confirmedPresence.toDiagnostics(),
            },
          );
          await connectPeer(peerId, bypassRetryBackoff: true);
        } catch (error) {
          _recordRuntimeEvent(
            category: 'connection',
            name: 'auto_recovery_failed',
            severity: 'warning',
            message: error.toString(),
            context: <String, Object?>{'peerId': peerId},
          );
          _connectionCoordinator.recordAttemptFailure(peerId, error);
        }
      }
    });
  }

  Future<void> setBackgroundServiceEnabled(bool enabled) async {
    _backgroundOfflineTimer?.cancel();
    if (_started && !_shutDown && !enabled) {
      await adapter.setPresence(selfIdentity.username, true);
    }
  }

  Future<void> dispose() async {
    await _shutdown(
      markOffline: true,
      signOut: false,
      clearLocalSession: false,
    );
  }

  Future<void> closeForAppExit(AppExitReason reason) async {
    _recordRuntimeEvent(
      category: 'runtime',
      name: 'app_exit_requested',
      context: <String, Object?>{'reason': reason.name},
    );
    await _shutdown(
      markOffline: true,
      signOut: false,
      clearLocalSession: false,
    );
  }

  Future<void> logOut() async {
    _recordRuntimeEvent(category: 'runtime', name: 'logout_requested');
    await _clearLocalSessionDataForShutdown();
    await _finishLogoutAfterLocalSessionClear();
  }

  Future<void> beginLogOut() async {
    _recordRuntimeEvent(category: 'runtime', name: 'logout_requested');
    _shutDown = true;
    await _clearLocalSessionDataForShutdown();
    unawaited(_finishLogoutAfterLocalSessionClear());
  }

  Future<void> deleteAccount(String password) async {
    _recordRuntimeEvent(category: 'runtime', name: 'account_delete_requested');
    await _reauthenticateForAccountDeletion(password);
    await _finishAccountDeletionAfterReauth(waitForRuntimeCleanup: true);
  }

  Future<void> beginDeleteAccount(
    String password, {
    void Function()? onDestructiveActionStarting,
  }) async {
    _recordRuntimeEvent(category: 'runtime', name: 'account_delete_requested');
    await _reauthenticateForAccountDeletion(password);
    onDestructiveActionStarting?.call();
    await _finishAccountDeletionAfterReauth(waitForRuntimeCleanup: false);
  }

  Future<void> _reauthenticateForAccountDeletion(String password) async {
    try {
      await adapter.reauthenticate(selfIdentity.username, password);
    } on AccountDeletionException {
      rethrow;
    } on Object catch (error) {
      throw AccountDeletionException(
        kind: AccountDeletionFailureKind.reauthenticationFailed,
        message: error.toString(),
        destructiveActionStarted: false,
        cause: error,
      );
    }
  }

  Future<void> _finishAccountDeletionAfterReauth({
    required bool waitForRuntimeCleanup,
  }) async {
    Object? deletionError;
    StackTrace? deletionStackTrace;
    var shouldClearLocalSession = false;
    try {
      await adapter.deleteAccount(
        selfIdentity.username,
        beforeAuthDeletion: _prepareForAccountAuthDeletion,
      );
      shouldClearLocalSession = true;
      _recordRuntimeEvent(
        category: 'runtime',
        name: 'account_delete_completed',
      );
    } catch (error, stackTrace) {
      deletionError = error;
      deletionStackTrace = stackTrace;
      shouldClearLocalSession =
          error is AccountDeletionException && error.destructiveActionStarted;
      _recordRuntimeEvent(
        category: 'runtime',
        name: 'account_delete_backend_failed',
        severity: 'warning',
        message: error.toString(),
      );
      errorRecorder?.call(
        error,
        stackTrace,
        source: 'runtime-account-delete',
        fatal: false,
      );
    }

    if (!shouldClearLocalSession) {
      Error.throwWithStackTrace(deletionError!, deletionStackTrace!);
    }

    final cleanupFuture = _shutdown(
      markOffline: true,
      signOut: false,
      clearLocalSession: false,
    );
    if (waitForRuntimeCleanup) {
      try {
        await cleanupFuture;
      } catch (error, stackTrace) {
        _recordRuntimeEvent(
          category: 'runtime',
          name: 'account_delete_runtime_shutdown_failed',
          severity: 'warning',
          message: error.toString(),
        );
        errorRecorder?.call(
          error,
          stackTrace,
          source: 'runtime-account-delete-shutdown',
          fatal: false,
        );
      }
    } else {
      unawaited(
        cleanupFuture.catchError((Object error, StackTrace stackTrace) {
          _recordRuntimeEvent(
            category: 'runtime',
            name: 'account_delete_runtime_shutdown_failed',
            severity: 'warning',
            message: error.toString(),
          );
          errorRecorder?.call(
            error,
            stackTrace,
            source: 'runtime-account-delete-shutdown',
            fatal: false,
          );
        }),
      );
    }

    try {
      await _clearLocalSessionDataForShutdown();
    } catch (error, stackTrace) {
      _recordRuntimeEvent(
        category: 'runtime',
        name: 'local_session_clear_failed_after_account_delete',
        severity: 'error',
        message: error.toString(),
      );
      errorRecorder?.call(
        error,
        stackTrace,
        source: 'runtime-account-delete-local-clear',
        fatal: true,
      );
      rethrow;
    }

    if (deletionError != null) {
      Error.throwWithStackTrace(deletionError, deletionStackTrace!);
    }
  }

  Future<void> _finishLogoutAfterLocalSessionClear() async {
    try {
      await _shutdown(
        markOffline: true,
        signOut: true,
        clearLocalSession: false,
      );
    } catch (error, stackTrace) {
      _recordRuntimeEvent(
        category: 'runtime',
        name: 'logout_cleanup_failed',
        severity: 'warning',
        message: error.toString(),
      );
      errorRecorder?.call(
        error,
        stackTrace,
        source: 'runtime-logout-cleanup',
        fatal: false,
      );
    }
  }

  Future<void> _prepareForAccountAuthDeletion() async {
    _recordRuntimeEvent(
      category: 'runtime',
      name: 'account_delete_auth_boundary_prepare_started',
    );
    _shutDown = true;
    final errors = <Object>[];
    final stacks = <StackTrace>[];

    Future<void> runStep(Future<void> Function() step) async {
      try {
        await step();
      } catch (error, stackTrace) {
        errors.add(error);
        stacks.add(stackTrace);
      }
    }

    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _friendRequestRefreshTimer?.cancel();
    _friendRequestRefreshTimer = null;
    _backgroundOfflineTimer?.cancel();
    _backgroundOfflineTimer = null;
    _dataEventNotifyThrottleTimer?.cancel();
    _dataEventNotifyThrottleTimer = null;
    cancelVoiceCallReconnectGrace();

    final sessions = brain?.getSessions() ?? const <Session>[];
    for (final session in sessions) {
      await runStep(() async {
        await endVoiceCallForPeer(
          session.peerId,
          notifyPeer: false,
          detail: 'Rain account is being deleted.',
        );
        await failActiveTransfersForPeer(
          session.peerId,
          'Transfer canceled because this account is being deleted.',
        );
        await _disconnectBrainPeer(
          session.peerId,
          PeerDisconnectIntent.localShutdown,
        );
        await unregisterPeerListener(session.peerId);
      });
    }
    for (final peerId in _registeredPeerListeners.toList()) {
      await runStep(() => unregisterPeerListener(peerId));
    }
    _connectionCoordinator.dispose();

    await runStep(cancelVoiceSignalingSubscriptions);
    await runStep(stopConnectionRequestRuntime);

    for (final subscription in _subscriptions.toList()) {
      await runStep(subscription.cancel);
    }
    _subscriptions.clear();

    for (final subscription in _presenceSubscriptions.values.toList()) {
      await runStep(subscription.cancel);
    }
    _presenceSubscriptions.clear();

    _recordRuntimeEvent(
      category: 'runtime',
      name: 'account_delete_auth_boundary_prepare_completed',
      severity: errors.isEmpty ? 'info' : 'warning',
      context: <String, Object?>{'errorCount': errors.length},
    );
    if (errors.isNotEmpty) {
      errorRecorder?.call(
        errors.first,
        stacks.first,
        source: 'runtime-account-delete-auth-boundary',
        fatal: false,
      );
    }
  }

  Future<void> markConversationRead(String username) {
    return _localMutations.run(() => friendStore.clearUnread(username));
  }

  Future<void> refreshRelationships({String? onlyUsername}) {
    return syncRelationships(
      onlyUsername: onlyUsername == null
          ? null
          : _normalizedUsername(onlyUsername),
    );
  }

  Future<void> refreshPeer(String username) {
    return refreshRelationships(onlyUsername: username);
  }

  Future<void> rejectFriend(String username) async {
    final normalizedUsername = _normalizedUsername(username);
    await failActiveTransfersForPeer(
      normalizedUsername,
      'Transfer canceled because the relationship changed.',
    );
    final existing = await _localMutations.run(
      () => friendStore.loadFriend(normalizedUsername),
    );
    if (existing?.state == FriendState.friend) {
      await unfriend(normalizedUsername);
      return;
    }
    if (existing?.state == FriendState.pendingIncoming) {
      await adapter.deleteFriendRequest(
        selfIdentity.username,
        normalizedUsername,
      );
    } else if (existing?.state == FriendState.pendingOutgoing) {
      await adapter.deleteFriendRequest(
        normalizedUsername,
        selfIdentity.username,
      );
    }
    await _localMutations.run(() => friendStore.reject(normalizedUsername));
    await stopTrackingPeer(normalizedUsername);
  }

  Future<void> resendMessage(String messageId) async {
    final queued = await _localMutations.run(
      () => offlineQueueStore.loadById(messageId),
    );
    if (queued == null) {
      return;
    }
    final friend = await _localMutations.run(
      () => friendStore.loadFriend(queued.to),
    );
    if (friend?.state != FriendState.friend) {
      await _localMutations.run(() async {
        await messageStore.markMessageStatus(messageId, MessageStatus.failed);
        await offlineQueueStore.markStatus(
          messageId,
          QueuedMessageStatus.failed,
        );
      });
      return;
    }

    final envelope = queued.toEnvelope(from: selfIdentity.username);
    final session = brain?.getSession(queued.to);
    await _localMutations.run(() async {
      await messageStore.markMessageStatus(messageId, MessageStatus.queued);
      await offlineQueueStore.markStatus(messageId, QueuedMessageStatus.queued);
    });

    if (brain == null || session?.state != SessionState.connected) {
      return;
    }

    await _localMutations.run(
      () => messageDeliveryService.sendEnvelope(
        envelope,
        sendChat: (String payload) async => session!.send(payload),
      ),
    );
  }

  Future<FriendRequestResult> sendFriendRequest(String username) async {
    final targetUsername = _normalizedUsername(username);
    final selfUsername = selfIdentity.username.trim().toLowerCase();
    if (targetUsername.isEmpty || targetUsername == selfUsername) {
      throw Exception('Cannot send friend request to yourself');
    }

    await syncRelationships(onlyUsername: targetUsername);

    final existing = await _localMutations.run(
      () => friendStore.loadFriend(targetUsername),
    );
    if (existing != null) {
      switch (existing.state) {
        case FriendState.friend:
          throw Exception('You are already friends with @$targetUsername.');
        case FriendState.pendingOutgoing:
          throw Exception(
            'A friend request to @$targetUsername is already pending.',
          );
        case FriendState.pendingIncoming:
          await acceptFriend(targetUsername);
          return FriendRequestResult.acceptedExisting;
        case FriendState.blocked:
          throw Exception('Unblock @$targetUsername before sending a request.');
        case FriendState.blockedByPeer:
          throw Exception(
            '@$targetUsername blocked you. You cannot send a request right now.',
          );
      }
    }

    final targetIdentity = await adapter.fetchIdentity(targetUsername);
    if (targetIdentity == null) {
      throw Exception(
        'User "@$targetUsername" was not found. Ask them to create an account first.',
      );
    }

    await adapter.writeFriendRequest(targetUsername, selfIdentity.username);
    await _localMutations.run(
      () => friendStore.upsertFriend(
        username: targetUsername,
        displayName: targetIdentity.displayName.isEmpty
            ? targetUsername
            : targetIdentity.displayName,
        state: FriendState.pendingOutgoing,
        addedAt: DateTime.now().millisecondsSinceEpoch,
        gender: _backendGender(targetIdentity.gender),
      ),
    );
    watchPresence(targetUsername);
    return FriendRequestResult.sent;
  }

  Future<void> sendMessage(String peerId, String content) async {
    var friend = await _localMutations.run(
      () => friendStore.loadFriend(peerId),
    );
    if (friend?.state != FriendState.friend) {
      await syncRelationships(onlyUsername: peerId);
      friend = await _localMutations.run(() => friendStore.loadFriend(peerId));
    }
    if (friend?.state != FriendState.friend) {
      throw StateError('Only friends can chat.');
    }
    final envelope = await _localMutations.run(
      () => messageStore.composeOutgoingEnvelope(
        from: selfIdentity.username,
        to: peerId,
        content: content,
      ),
    );

    final session = brain?.getSession(peerId);
    if (brain == null || session?.state != SessionState.connected) {
      await _localMutations.run(
        () => messageDeliveryService.queueOutgoing(envelope),
      );
      return;
    }

    await _localMutations.run(
      () => messageDeliveryService.sendEnvelope(
        envelope,
        sendChat: (String payload) async => session!.send(payload),
      ),
    );
    _recordDataEvent(peerId, DateTime.now().millisecondsSinceEpoch);
    await _localMutations.run(() => friendStore.clearUnread(peerId));
  }

  Future<void> sendFile({
    required String peerId,
    required String fileName,
    required int fileSize,
    required Stream<List<int>> Function() openRead,
    String? localPath,
    String? mimeType,
  }) async {
    final normalizedPeerId = _normalizedUsername(peerId);
    if (fileSize > maxFileTransferBytes) {
      throw StateError(
        'Files are limited to ${formatFileTransferSize(maxFileTransferBytes)}.',
      );
    }
    if (fileSize < 0) {
      throw StateError('File size is invalid.');
    }

    await assertCanTransferFile(normalizedPeerId);
    RuntimeInteractionGuard.canStartFileTransfer(
      peerId: normalizedPeerId,
      voiceCallState: _voiceCallState,
    ).throwIfDenied();
    final session = connectedSession(normalizedPeerId);
    if (session == null) {
      throw StateError('Connect first.');
    }
    if (await fileTransferStore.hasActiveTransferForPeer(normalizedPeerId)) {
      throw StateError('Finish the active file transfer first.');
    }
    await ensureFileChannelReady(normalizedPeerId);

    final safeName = sanitizeFileName(fileName);
    final transferEnvelope = await _localMutations.run(
      () => messageStore.composeOutgoingEnvelope(
        from: selfIdentity.username,
        to: normalizedPeerId,
        content: FileMessageContent(
          transferId: '',
          fileName: safeName,
          fileSize: fileSize,
          mimeType: mimeType,
        ).encode(),
        type: MessageType.file,
        trackSequence: false,
      ),
    );
    final transferId = transferEnvelope.id;
    final content = FileMessageContent(
      transferId: transferId,
      fileName: safeName,
      fileSize: fileSize,
      mimeType: mimeType,
    ).encode();
    final envelope = MessageEnvelope(
      id: transferEnvelope.id,
      from: transferEnvelope.from,
      to: transferEnvelope.to,
      content: content,
      sentAt: transferEnvelope.sentAt,
      seq: transferEnvelope.seq,
      type: MessageType.file,
    );
    final now = DateTime.now().millisecondsSinceEpoch;
    _outgoingFileSources[transferId] = OutgoingFileSource(
      openRead: openRead,
      localPath: localPath,
    );

    await _localMutations.run(() async {
      await messageStore.storeOutgoingEnvelope(
        envelope,
        status: MessageStatus.sending,
      );
      await fileTransferStore.upsert(
        FileTransferRecord(
          id: transferId,
          peerId: normalizedPeerId,
          messageId: envelope.id,
          direction: FileTransferDirection.outgoing,
          fileName: safeName,
          fileSize: fileSize,
          mimeType: mimeType,
          localPath: localPath,
          bytesTransferred: 0,
          state: FileTransferState.offered,
          createdAt: now,
          updatedAt: now,
        ),
      );
    });

    final offer = FileTransferFrame.offer(
      transferId: transferId,
      messageId: envelope.id,
      fileName: safeName,
      fileSize: fileSize,
      mimeType: mimeType,
      sentAt: envelope.sentAt,
      seq: envelope.seq,
    );
    try {
      brain!.send(normalizedPeerId, SessionChannel.file, offer.encode());
      _recordDataEvent(normalizedPeerId, DateTime.now().millisecondsSinceEpoch);
      await messageStore.markMessageStatus(envelope.id, MessageStatus.sent);
    } catch (error) {
      await markTransferFailed(transferId, 'File offer failed: $error');
      rethrow;
    }
  }

  Future<void> acceptFileTransfer(String transferId) async {
    final transfer = await fileTransferStore.loadById(transferId);
    if (transfer == null) {
      throw StateError('File transfer not found.');
    }
    if (transfer.direction != FileTransferDirection.incoming ||
        transfer.state != FileTransferState.offered) {
      throw StateError('This file transfer cannot be accepted.');
    }
    await assertCanTransferFile(transfer.peerId);
    RuntimeInteractionGuard.canAcceptFileTransfer(
      peerId: transfer.peerId,
      transferId: transfer.id,
      voiceCallState: _voiceCallState,
    ).throwIfDenied();
    if (connectedSession(transfer.peerId) == null) {
      throw StateError('Connect first.');
    }
    await ensureFileChannelReady(transfer.peerId);
    final paths = await prepareReceivePaths(transfer);
    await fileTransferStore.markState(
      transfer.id,
      FileTransferState.receiving,
      bytesTransferred: 0,
      localPath: paths.finalPath,
      tempPath: paths.tempPath,
    );
    _receiveProgressOffsets[transfer.id] = 0;
    brain!.send(
      transfer.peerId,
      SessionChannel.file,
      FileTransferFrame.accept(transfer.id).encode(),
    );
  }

  Future<void> rejectFileTransfer(String transferId) async {
    final transfer = await fileTransferStore.loadById(transferId);
    if (transfer == null) {
      return;
    }
    await fileTransferStore.markState(
      transfer.id,
      FileTransferState.rejected,
      error: 'Rejected.',
    );
    clearTransferRuntimeState(transfer.id);
    sendFileControlIfConnected(
      transfer.peerId,
      FileTransferFrame.reject(transfer.id, 'Rejected.'),
    );
  }

  Future<void> cancelFileTransfer(String transferId) async {
    final transfer = await fileTransferStore.loadById(transferId);
    if (transfer == null) {
      return;
    }
    _canceledTransfers.add(transfer.id);
    await deleteTempFile(transfer);
    await fileTransferStore.markState(
      transfer.id,
      FileTransferState.canceled,
      error: 'Canceled.',
    );
    clearTransferRuntimeState(transfer.id);
    sendFileControlIfConnected(
      transfer.peerId,
      FileTransferFrame.cancel(transfer.id, 'Canceled.'),
    );
  }

  void _recordSessionAttemptState(Session session) {
    switch (session.state) {
      case SessionState.connected:
        _recordRuntimeEvent(
          category: 'connection',
          name: 'session_connected',
          context: _sessionEventContext(session),
        );
        _recoverableDisconnectedPeers.remove(session.peerId);
        clearVoiceCallReconnectingForPeer(session.peerId);
        _connectionCoordinator.recordAttemptSuccess(session.peerId);
        break;
      case SessionState.failed:
        _recordRuntimeEvent(
          category: 'connection',
          name: 'session_failed',
          severity: 'warning',
          message: session.error ?? session.detail,
          context: _sessionEventContext(session),
        );
        _connectionCoordinator.recordAttemptFailure(
          session.peerId,
          session.error ?? session.detail,
        );
        failVoiceCallForPeer(
          session.peerId,
          'Peer connection failed. Voice call ended.',
        );
        unawaited(
          failActiveTransfersForPeer(
            session.peerId,
            'Connection lost. Transfer canceled.',
          ),
        );
        break;
      case SessionState.connecting:
      case SessionState.reconnecting:
        break;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_started || _shutDown) {
      return;
    }
    handleVoiceCallAppLifecycleState(state);

    switch (state) {
      case AppLifecycleState.resumed:
        _presenceHeartbeatPaused = false;
        _backgroundOfflineTimer?.cancel();
        unawaited(cleanupStaleVoiceCallArtifacts('resume'));
        unawaited(
          handleNetworkAvailable(
            'App resumed. Refreshing peer connection paths.',
          ),
        );
        break;
      case AppLifecycleState.inactive:
        break;
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        _presenceHeartbeatPaused = true;
        _backgroundOfflineTimer?.cancel();
        unawaited(_setPresenceOfflineSafely('app_${state.name}'));
        break;
      case AppLifecycleState.detached:
        _presenceHeartbeatPaused = true;
        _backgroundOfflineTimer?.cancel();
        unawaited(closeForAppExit(AppExitReason.lifecycleDetached));
        break;
    }
  }

  Future<void> _shutdown({
    required bool markOffline,
    required bool signOut,
    required bool clearLocalSession,
  }) async {
    final existing = _shutdownFuture;
    if (existing != null) {
      try {
        await existing;
      } finally {
        await _completeLogoutSessionClearIfNeeded(
          signOut: signOut,
          clearLocalSession: clearLocalSession,
        );
      }
      return;
    }
    _recordRuntimeEvent(
      category: 'runtime',
      name: 'shutdown_started',
      context: <String, Object?>{
        'markOffline': markOffline,
        'signOut': signOut,
        'clearLocalSession': clearLocalSession,
      },
    );
    _shutDown = true;
    final shutdownFuture = _runShutdown(
      markOffline: markOffline,
      signOut: signOut,
      clearLocalSession: clearLocalSession,
    );
    _shutdownFuture = shutdownFuture;
    await shutdownFuture;
    _recordRuntimeEvent(category: 'runtime', name: 'shutdown_completed');
  }

  Future<void> _runShutdown({
    required bool markOffline,
    required bool signOut,
    required bool clearLocalSession,
  }) async {
    const keepBackgroundPresence = false;

    Object? cleanupError;
    StackTrace? cleanupStackTrace;
    try {
      final activeVoicePeer = _voiceCallState.peerId;
      if (activeVoicePeer != null) {
        try {
          await endVoiceCallForPeer(
            activeVoicePeer,
            notifyPeer: false,
            detail: 'Rain is closing.',
          );
        } catch (_) {
          // Ignore errors during cleanup
        }
      }

      if (brain != null) {
        for (final session in brain!.getSessions()) {
          try {
            await endVoiceCallForPeer(
              session.peerId,
              notifyPeer: false,
              detail: 'Rain is closing.',
            );
            await failActiveTransfersForPeer(
              session.peerId,
              'Transfer canceled because Rain is closing.',
            );
            await _disconnectBrainPeer(
              session.peerId,
              PeerDisconnectIntent.localShutdown,
            );
            await unregisterPeerListener(session.peerId);
          } catch (error) {
            // Ignore errors during cleanup
          }
        }
        for (final peerId in _registeredPeerListeners.toList()) {
          try {
            await unregisterPeerListener(peerId);
          } catch (_) {
            // Ignore errors during cleanup
          }
        }
      }

      if (markOffline && _started && !keepBackgroundPresence) {
        try {
          await adapter.setPresence(selfIdentity.username, false);
        } catch (error) {
          // Ignore permission errors during logout
        }
      }

      WidgetsBinding.instance.removeObserver(this);
      _backgroundOfflineTimer?.cancel();
      _dataEventNotifyThrottleTimer?.cancel();
      _dataEventNotifyThrottleTimer = null;
      cancelVoiceCallReconnectGrace();
      await disposeCurrentVoiceCallSession();
      _heartbeatTimer?.cancel();
      _friendRequestRefreshTimer?.cancel();
      _connectionCoordinator.dispose();
      await stopConnectionRequestRuntime();
      await closeAllReceiveSinks(reason: 'shutdown');

      for (final subscription in _subscriptions) {
        await subscription.cancel();
      }
      _subscriptions.clear();

      for (final subscription in _presenceSubscriptions.values) {
        await subscription.cancel();
      }
      _presenceSubscriptions.clear();
      await _voiceCallStateController.close();
      await _peerConnectivityChangeController.close();
      await _connectionRequestStateController.close();
    } catch (error, stackTrace) {
      cleanupError = error;
      cleanupStackTrace = stackTrace;
      _recordRuntimeEvent(
        category: 'runtime',
        name: 'shutdown_cleanup_failed',
        severity: 'warning',
        message: error.toString(),
      );
      errorRecorder?.call(
        error,
        stackTrace,
        source: 'runtime-shutdown-cleanup',
        fatal: false,
      );
    } finally {
      await _completeLogoutSessionClearIfNeeded(
        signOut: signOut,
        clearLocalSession: clearLocalSession,
      );
    }

    if (cleanupError != null && !clearLocalSession) {
      Error.throwWithStackTrace(cleanupError, cleanupStackTrace!);
    }
  }

  Future<void> _completeLogoutSessionClearIfNeeded({
    required bool signOut,
    required bool clearLocalSession,
  }) async {
    if (clearLocalSession) {
      await _clearLocalSessionDataForShutdown();
    }

    if (signOut) {
      await _signOutSafely();
    }
  }

  Future<void> _clearLocalSessionDataForShutdown() async {
    try {
      await _localMutations.run(database.clearSessionData);
      _recordRuntimeEvent(category: 'runtime', name: 'local_session_cleared');
    } catch (error, stackTrace) {
      _recordRuntimeEvent(
        category: 'runtime',
        name: 'local_session_clear_failed',
        severity: 'error',
        message: error.toString(),
      );
      errorRecorder?.call(
        error,
        stackTrace,
        source: 'runtime-local-session-clear',
        fatal: true,
      );
      rethrow;
    }
  }

  Future<void> _signOutSafely() async {
    try {
      await adapter.signOut();
      _recordRuntimeEvent(category: 'runtime', name: 'sign_out_completed');
    } catch (error, stackTrace) {
      _recordRuntimeEvent(
        category: 'runtime',
        name: 'sign_out_failed_after_local_clear',
        severity: 'warning',
        message: error.toString(),
      );
      errorRecorder?.call(
        error,
        stackTrace,
        source: 'runtime-sign-out',
        fatal: false,
      );
    }
  }
}
