enum ConnectionMode {
  auto,
  webRtcAuto,
  webRtcDirectOnly,
  webRtcRelayOnly,
  irohFallback,
}

extension ConnectionModeX on ConnectionMode {
  bool get isIroh => this == ConnectionMode.irohFallback;

  bool get canForceIrohRoute => false;
}

enum ConnectionLayer {
  preflight,
  webRtcDirect,
  webRtcPrimaryRelay,
  webRtcBackupRelay,
  webRtcFullRestart,
  iroh,
}

enum ConnectionStepState {
  pending,
  running,
  retrying,
  succeeded,
  failed,
  skipped,
  canceled,
}

enum ConnectionFailureCode {
  peerOffline,
  notFriends,
  blocked,
  networkOffline,
  backendUnavailable,
  signalingPermissionDenied,
  staleRoomCleanupFailed,
  directPathBlocked,
  turnCredentialsUnavailable,
  turnProviderTimedOut,
  dataChannelTimeout,
  irohAddressTimeout,
  irohHandshakeRejected,
  irohConnectFailed,
  globalBudgetExceeded,
  userCanceled,
  unknown,
}

enum ConnectionCancelReason {
  userCanceled,
  disconnect,
  logout,
  networkLost,
  appShutdown,
  supersededAttempt,
  globalBudgetExceeded,
}

enum ConnectionFallbackChoice {
  tryAuto,
  tryRelay,
  tryIroh,
  cancel,
}

class ConnectionFallbackRequest {
  const ConnectionFallbackRequest({
    required this.peerId,
    required this.attemptId,
    required this.failedLayer,
    required this.failureCode,
    required this.userMessage,
    this.choices = const <ConnectionFallbackChoice>[
      ConnectionFallbackChoice.tryAuto,
      ConnectionFallbackChoice.tryRelay,
      ConnectionFallbackChoice.tryIroh,
      ConnectionFallbackChoice.cancel,
    ],
  });

  final String peerId;
  final String attemptId;
  final ConnectionLayer failedLayer;
  final ConnectionFailureCode failureCode;
  final String userMessage;
  final List<ConnectionFallbackChoice> choices;
}

class ConnectionPolicy {
  const ConnectionPolicy({
    required this.mode,
    this.askBeforeFallback = true,
    this.rememberForSession = false,
  });

  const ConnectionPolicy.defaults()
    : mode = ConnectionMode.auto,
      askBeforeFallback = true,
      rememberForSession = false;

  final ConnectionMode mode;
  final bool askBeforeFallback;
  final bool rememberForSession;

  ConnectionPolicy copyWith({
    ConnectionMode? mode,
    bool? askBeforeFallback,
    bool? rememberForSession,
  }) {
    return ConnectionPolicy(
      mode: mode ?? this.mode,
      askBeforeFallback: askBeforeFallback ?? this.askBeforeFallback,
      rememberForSession: rememberForSession ?? this.rememberForSession,
    );
  }
}

class ConnectionAttemptStep {
  const ConnectionAttemptStep({
    required this.layer,
    required this.state,
    required this.userMessage,
    required this.startedAt,
    this.failureCode,
    this.technicalDetail,
    this.endedAt,
    this.retryCount = 0,
  });

  const ConnectionAttemptStep.pending({
    required ConnectionLayer layer,
    required String userMessage,
    required int startedAt,
  }) : this(
         layer: layer,
         state: ConnectionStepState.pending,
         userMessage: userMessage,
         startedAt: startedAt,
       );

  final ConnectionLayer layer;
  final ConnectionStepState state;
  final ConnectionFailureCode? failureCode;
  final String userMessage;
  final String? technicalDetail;
  final int startedAt;
  final int? endedAt;
  final int retryCount;

  ConnectionAttemptStep copyWith({
    ConnectionLayer? layer,
    ConnectionStepState? state,
    ConnectionFailureCode? failureCode,
    String? userMessage,
    String? technicalDetail,
    int? startedAt,
    int? endedAt,
    int? retryCount,
  }) {
    return ConnectionAttemptStep(
      layer: layer ?? this.layer,
      state: state ?? this.state,
      failureCode: failureCode ?? this.failureCode,
      userMessage: userMessage ?? this.userMessage,
      technicalDetail: technicalDetail ?? this.technicalDetail,
      startedAt: startedAt ?? this.startedAt,
      endedAt: endedAt ?? this.endedAt,
      retryCount: retryCount ?? this.retryCount,
    );
  }
}

class ConnectionTimeline {
  const ConnectionTimeline({
    required this.peerId,
    required this.attemptId,
    required this.policy,
    this.steps = const <ConnectionAttemptStep>[],
    this.fullHistory = const <ConnectionAttemptStep>[],
    this.activeLayer,
    this.canCancel = false,
    this.canRetry = false,
    this.fallbackPromptAlreadyShown = false,
    this.globalBudgetExceeded = false,
  });

  factory ConnectionTimeline.initial({
    required String peerId,
    required String attemptId,
    required ConnectionPolicy policy,
  }) {
    return ConnectionTimeline(
      peerId: peerId,
      attemptId: attemptId,
      policy: policy,
    );
  }

  static const int maxVisibleSteps = 24;

  final String peerId;
  final String attemptId;
  final ConnectionPolicy policy;
  final List<ConnectionAttemptStep> steps;
  final List<ConnectionAttemptStep> fullHistory;
  final ConnectionLayer? activeLayer;
  final bool canCancel;
  final bool canRetry;
  final bool fallbackPromptAlreadyShown;
  final bool globalBudgetExceeded;

  bool get shouldShowFallbackPrompt =>
      policy.askBeforeFallback && !fallbackPromptAlreadyShown;

  ConnectionTimeline addStep(ConnectionAttemptStep step) {
    final nextHistory = List<ConnectionAttemptStep>.unmodifiable(
      <ConnectionAttemptStep>[...fullHistory, step],
    );
    final nextVisible = nextHistory.length <= maxVisibleSteps
        ? nextHistory
        : nextHistory.sublist(nextHistory.length - maxVisibleSteps);
    return copyWith(steps: nextVisible, fullHistory: nextHistory);
  }

  ConnectionTimeline markFallbackPromptShown() {
    return copyWith(fallbackPromptAlreadyShown: true);
  }

  ConnectionTimeline copyWith({
    String? peerId,
    String? attemptId,
    ConnectionPolicy? policy,
    List<ConnectionAttemptStep>? steps,
    List<ConnectionAttemptStep>? fullHistory,
    ConnectionLayer? activeLayer,
    bool? canCancel,
    bool? canRetry,
    bool? fallbackPromptAlreadyShown,
    bool? globalBudgetExceeded,
  }) {
    return ConnectionTimeline(
      peerId: peerId ?? this.peerId,
      attemptId: attemptId ?? this.attemptId,
      policy: policy ?? this.policy,
      steps: List<ConnectionAttemptStep>.unmodifiable(steps ?? this.steps),
      fullHistory: List<ConnectionAttemptStep>.unmodifiable(
        fullHistory ?? this.fullHistory,
      ),
      activeLayer: activeLayer ?? this.activeLayer,
      canCancel: canCancel ?? this.canCancel,
      canRetry: canRetry ?? this.canRetry,
      fallbackPromptAlreadyShown:
          fallbackPromptAlreadyShown ?? this.fallbackPromptAlreadyShown,
      globalBudgetExceeded: globalBudgetExceeded ?? this.globalBudgetExceeded,
    );
  }
}
