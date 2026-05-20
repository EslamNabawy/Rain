import 'dart:async';
import 'dart:math';

import 'connection_command_models.dart';
import 'connection_failure_messages.dart';
import 'connection_run_token.dart';
import 'connection_timeouts.dart';

typedef ConnectionClock = int Function();
typedef ConnectionRunIdFactory = String Function();

class ConnectionCommandTimeoutConfig {
  const ConnectionCommandTimeoutConfig({
    this.webRtcDirect = ConnectionTimeouts.webRtcDirect,
    this.webRtcPrimaryRelay = ConnectionTimeouts.webRtcPrimaryRelay,
    this.webRtcBackupRelay = ConnectionTimeouts.webRtcBackupRelay,
    this.webRtcFullRestart = ConnectionTimeouts.webRtcFullRestart,
    this.iroh = ConnectionTimeouts.iroh,
    this.globalBudget = ConnectionTimeouts.globalBudget,
    this.retryBaseDelay = ConnectionTimeouts.retryBaseDelay,
    this.retryMaxJitter = ConnectionTimeouts.retryMaxJitter,
  });

  final Duration webRtcDirect;
  final Duration webRtcPrimaryRelay;
  final Duration webRtcBackupRelay;
  final Duration webRtcFullRestart;
  final Duration iroh;
  final Duration globalBudget;
  final Duration retryBaseDelay;
  final Duration retryMaxJitter;
}

class ConnectionLayerResult {
  const ConnectionLayerResult.succeeded()
    : succeeded = true,
      failureCode = null,
      technicalDetail = null;

  const ConnectionLayerResult.failed(
    ConnectionFailureCode this.failureCode, {
    this.technicalDetail,
  }) : succeeded = false;

  final bool succeeded;
  final ConnectionFailureCode? failureCode;
  final String? technicalDetail;
}

abstract class ConnectionCommandTransport {
  Future<ConnectionLayerResult> runLayer({
    required String peerId,
    required ConnectionLayer layer,
    required ConnectionRunToken token,
    required Duration timeout,
  });

  Future<void> cancelLayer({
    required String peerId,
    required ConnectionLayer layer,
    required ConnectionRunToken token,
  });
}

class IdleConnectionCommandTransport implements ConnectionCommandTransport {
  @override
  Future<ConnectionLayerResult> runLayer({
    required String peerId,
    required ConnectionLayer layer,
    required ConnectionRunToken token,
    required Duration timeout,
  }) {
    return Completer<ConnectionLayerResult>().future;
  }

  @override
  Future<void> cancelLayer({
    required String peerId,
    required ConnectionLayer layer,
    required ConnectionRunToken token,
  }) async {}
}

class ConnectionCommandOrchestrator {
  ConnectionCommandOrchestrator({
    ConnectionClock? now,
    ConnectionRunIdFactory? runIdFactory,
    ConnectionCommandTransport? transport,
    ConnectionCommandTimeoutConfig timeouts =
        const ConnectionCommandTimeoutConfig(),
  }) : _now = now ?? (() => DateTime.now().millisecondsSinceEpoch),
       _runIdFactory =
           runIdFactory ??
           (() => DateTime.now().microsecondsSinceEpoch.toString()),
       _transport = transport ?? IdleConnectionCommandTransport(),
       _timeouts = timeouts;

  final ConnectionClock _now;
  final ConnectionRunIdFactory _runIdFactory;
  final ConnectionCommandTransport _transport;
  final ConnectionCommandTimeoutConfig _timeouts;

  final Map<String, ConnectionPolicy> _sessionPolicies =
      <String, ConnectionPolicy>{};
  final Map<String, ConnectionTimeline> _timelines =
      <String, ConnectionTimeline>{};
  final Map<String, StreamController<ConnectionTimeline>> _timelineControllers =
      <String, StreamController<ConnectionTimeline>>{};
  final Map<String, ConnectionRunToken> _activeRuns =
      <String, ConnectionRunToken>{};
  final Map<String, int> _generations = <String, int>{};
  final Map<String, Timer> _globalBudgetTimers = <String, Timer>{};
  final Map<String, ConnectionFallbackRequest> _pendingFallbacks =
      <String, ConnectionFallbackRequest>{};
  final StreamController<ConnectionFallbackRequest> _fallbackController =
      StreamController<ConnectionFallbackRequest>.broadcast(sync: true);

  static List<ConnectionLayer> layersForPolicy(ConnectionPolicy policy) {
    return switch (policy.mode) {
      ConnectionMode.auto => <ConnectionLayer>[
        ConnectionLayer.preflight,
        ConnectionLayer.webRtcDirect,
        ConnectionLayer.webRtcPrimaryRelay,
        ConnectionLayer.webRtcBackupRelay,
        ConnectionLayer.webRtcFullRestart,
        ConnectionLayer.iroh,
      ],
      ConnectionMode.webRtcAuto => <ConnectionLayer>[
        ConnectionLayer.preflight,
        ConnectionLayer.webRtcDirect,
        ConnectionLayer.webRtcPrimaryRelay,
        ConnectionLayer.webRtcBackupRelay,
        ConnectionLayer.webRtcFullRestart,
      ],
      ConnectionMode.webRtcDirectOnly => <ConnectionLayer>[
        ConnectionLayer.preflight,
        ConnectionLayer.webRtcDirect,
      ],
      ConnectionMode.webRtcRelayOnly => <ConnectionLayer>[
        ConnectionLayer.preflight,
        ConnectionLayer.webRtcPrimaryRelay,
        ConnectionLayer.webRtcBackupRelay,
        ConnectionLayer.webRtcFullRestart,
      ],
      ConnectionMode.irohFallback => <ConnectionLayer>[
        ConnectionLayer.preflight,
        ConnectionLayer.iroh,
      ],
    };
  }

  static bool isRetryable(ConnectionFailureCode code) {
    return switch (code) {
      ConnectionFailureCode.staleRoomCleanupFailed ||
      ConnectionFailureCode.backendUnavailable ||
      ConnectionFailureCode.dataChannelTimeout => true,
      _ => false,
    };
  }

  static Duration retryDelay(Random random) {
    final jitter = random.nextInt(
      ConnectionTimeouts.retryMaxJitter.inMilliseconds + 1,
    );
    return ConnectionTimeouts.retryBaseDelay + Duration(milliseconds: jitter);
  }

  Future<void> connect(String peerId, {ConnectionPolicy? policy}) async {
    final normalizedPeerId = peerId.trim();
    if (normalizedPeerId.isEmpty || _activeRuns.containsKey(normalizedPeerId)) {
      return;
    }

    final attemptPolicy =
        policy ??
        _sessionPolicies[normalizedPeerId] ??
        const ConnectionPolicy.defaults();
    final runId = _runIdFactory();
    final generation = (_generations[normalizedPeerId] ?? 0) + 1;
    _generations[normalizedPeerId] = generation;
    _activeRuns[normalizedPeerId] = ConnectionRunToken(
      peerId: normalizedPeerId,
      runId: runId,
      generation: generation,
      startedAt: _now(),
    );

    var timeline =
        ConnectionTimeline.initial(
          peerId: normalizedPeerId,
          attemptId: runId,
          policy: attemptPolicy,
        ).addStep(
          ConnectionAttemptStep.pending(
            layer: ConnectionLayer.preflight,
            userMessage: 'Checking peer.',
            startedAt: _now(),
          ),
        );
    _emit(timeline);

    final runningStep = timeline.steps.last.copyWith(
      state: ConnectionStepState.running,
    );
    timeline = _replaceLastStep(
      timeline,
      runningStep,
    ).copyWith(activeLayer: ConnectionLayer.preflight, canCancel: true);
    _emit(timeline);
    _globalBudgetTimers[normalizedPeerId]?.cancel();
    _globalBudgetTimers[normalizedPeerId] = Timer(
      _timeouts.globalBudget,
      () => unawaited(_handleGlobalBudgetExceeded(normalizedPeerId)),
    );
    unawaited(_runPolicy(normalizedPeerId));
  }

  Future<void> retry(String peerId, {ConnectionPolicy? overridePolicy}) async {
    await connect(peerId, policy: overridePolicy);
  }

  Future<void> cancel(
    String peerId, {
    ConnectionCancelReason reason = ConnectionCancelReason.userCanceled,
  }) async {
    final normalizedPeerId = peerId.trim();
    final timeline = _timelines[normalizedPeerId];
    final token = _activeRuns.remove(normalizedPeerId);
    _globalBudgetTimers.remove(normalizedPeerId)?.cancel();
    _pendingFallbacks.remove(normalizedPeerId);
    if (token == null) {
      return;
    }
    token.cancel(reason);
    final activeLayer = timeline?.activeLayer ?? ConnectionLayer.preflight;
    await _transport.cancelLayer(
      peerId: normalizedPeerId,
      layer: activeLayer,
      token: token,
    );
    final current = _timelines[normalizedPeerId];
    if (current == null || current.steps.isEmpty) {
      return;
    }
    _emit(
      _replaceLastStep(
        current,
        current.steps.last.copyWith(
          state: ConnectionStepState.canceled,
          failureCode: _failureForCancelReason(reason),
          endedAt: _now(),
        ),
      ).copyWith(canCancel: false, canRetry: false),
    );
  }

  Future<void> disconnect(String peerId) async {
    await cancel(peerId, reason: ConnectionCancelReason.disconnect);
  }

  void rememberPolicyForSession(String peerId, ConnectionPolicy policy) {
    final normalizedPeerId = peerId.trim();
    if (normalizedPeerId.isEmpty) {
      return;
    }
    _sessionPolicies[normalizedPeerId] = policy;
  }

  void clearSessionPolicy(String peerId) {
    _sessionPolicies.remove(peerId.trim());
  }

  ConnectionPolicy policyForPeer(String peerId) {
    return _sessionPolicies[peerId.trim()] ?? const ConnectionPolicy.defaults();
  }

  Stream<ConnectionFallbackRequest> get fallbackRequests =>
      _fallbackController.stream;

  Future<void> resolveFallback({
    required String peerId,
    required ConnectionFallbackChoice choice,
    bool rememberForSession = false,
  }) async {
    final normalizedPeerId = peerId.trim();
    final request = _pendingFallbacks.remove(normalizedPeerId);
    final token = _activeRuns[normalizedPeerId];
    final timeline = _timelines[normalizedPeerId];
    if (request == null || token == null || timeline == null) {
      return;
    }
    if (choice == ConnectionFallbackChoice.cancel) {
      await cancel(normalizedPeerId);
      return;
    }

    final policy = _policyForFallbackChoice(
      choice,
    ).copyWith(rememberForSession: rememberForSession);
    if (rememberForSession) {
      rememberPolicyForSession(normalizedPeerId, policy);
    }
    _emit(timeline.copyWith(policy: policy, canCancel: true, canRetry: false));
    unawaited(_runPolicy(normalizedPeerId));
  }

  Stream<ConnectionTimeline> timelineStream(String peerId) {
    return _controllerFor(peerId.trim()).stream;
  }

  ConnectionTimeline? currentTimeline(String peerId) {
    return _timelines[peerId.trim()];
  }

  void dispose() {
    for (final token in _activeRuns.values) {
      token.cancel(ConnectionCancelReason.appShutdown);
    }
    for (final timer in _globalBudgetTimers.values) {
      timer.cancel();
    }
    _activeRuns.clear();
    _globalBudgetTimers.clear();
    _pendingFallbacks.clear();
    _sessionPolicies.clear();
    _timelines.clear();
    _generations.clear();
    for (final controller in _timelineControllers.values) {
      unawaited(controller.close());
    }
    _timelineControllers.clear();
    unawaited(_fallbackController.close());
  }

  void _emit(ConnectionTimeline timeline) {
    _timelines[timeline.peerId] = timeline;
    final controller = _controllerFor(timeline.peerId);
    if (!controller.isClosed) {
      controller.add(timeline);
    }
  }

  Future<void> _runPolicy(String peerId) async {
    final token = _activeRuns[peerId];
    var timeline = _timelines[peerId];
    if (token == null || timeline == null) {
      return;
    }
    final layers = layersForPolicy(timeline.policy);

    for (final layer in layers) {
      token.throwIfCanceled();
      timeline = _timelines[peerId];
      if (timeline == null || !_isCurrentToken(peerId, token)) {
        return;
      }
      timeline = _ensureLayerRunning(timeline, layer);

      var retryCount = 0;
      while (true) {
        final result = await _transport.runLayer(
          peerId: peerId,
          layer: layer,
          token: token,
          timeout: _timeoutForLayer(layer),
        );
        if (!_isCurrentToken(peerId, token)) {
          return;
        }

        timeline = _timelines[peerId];
        if (timeline == null) {
          return;
        }
        if (result.succeeded) {
          timeline = _replaceLastStep(
            timeline,
            timeline.steps.last.copyWith(
              state: ConnectionStepState.succeeded,
              endedAt: _now(),
              retryCount: retryCount,
            ),
          );
          _emit(timeline);
          if (layer == ConnectionLayer.preflight) {
            break;
          }
          _finishRun(peerId, canRetry: false);
          return;
        }

        final failureCode = result.failureCode ?? ConnectionFailureCode.unknown;
        if (retryCount == 0 && isRetryable(failureCode)) {
          retryCount += 1;
          timeline = _replaceLastStep(
            timeline,
            timeline.steps.last.copyWith(
              state: ConnectionStepState.retrying,
              failureCode: failureCode,
              technicalDetail: result.technicalDetail,
              retryCount: retryCount,
            ),
          );
          _emit(timeline);
          await Future<void>.delayed(_retryDelay());
          if (!_isCurrentToken(peerId, token)) {
            return;
          }
          timeline = _timelines[peerId];
          if (timeline == null) {
            return;
          }
          timeline = _replaceLastStep(
            timeline,
            timeline.steps.last.copyWith(
              state: ConnectionStepState.running,
              retryCount: retryCount,
            ),
          );
          _emit(timeline);
          continue;
        }

        timeline = _replaceLastStep(
          timeline,
          timeline.steps.last.copyWith(
            state: ConnectionStepState.failed,
            failureCode: failureCode,
            technicalDetail: result.technicalDetail,
            endedAt: _now(),
            retryCount: retryCount,
          ),
        );
        _emit(timeline);
        break;
      }
    }

    timeline = _timelines[peerId];
    if (timeline != null && _shouldOfferFallback(timeline)) {
      final failedStep = timeline.steps.last;
      final failureCode =
          failedStep.failureCode ?? ConnectionFailureCode.unknown;
      timeline = timeline.markFallbackPromptShown().copyWith(
        canCancel: true,
        canRetry: false,
      );
      _emit(timeline);
      final request = ConnectionFallbackRequest(
        peerId: peerId,
        attemptId: timeline.attemptId,
        failedLayer: failedStep.layer,
        failureCode: failureCode,
        userMessage: ConnectionFailureMessages.userMessage(failureCode),
      );
      _pendingFallbacks[peerId] = request;
      if (!_fallbackController.isClosed) {
        _fallbackController.add(request);
      }
      return;
    }
    _finishRun(peerId, canRetry: true);
  }

  Future<void> _handleGlobalBudgetExceeded(String peerId) async {
    final token = _activeRuns.remove(peerId);
    var timeline = _timelines[peerId];
    if (token == null || timeline == null) {
      return;
    }
    token.cancel(ConnectionCancelReason.globalBudgetExceeded);
    final activeLayer = timeline.activeLayer ?? ConnectionLayer.preflight;
    await _transport.cancelLayer(
      peerId: peerId,
      layer: activeLayer,
      token: token,
    );
    timeline = _replaceLastStep(
      timeline,
      timeline.steps.last.copyWith(
        state: ConnectionStepState.failed,
        failureCode: ConnectionFailureCode.globalBudgetExceeded,
        endedAt: _now(),
      ),
    ).copyWith(canCancel: false, canRetry: true, globalBudgetExceeded: true);
    _emit(timeline);
  }

  void _finishRun(String peerId, {required bool canRetry}) {
    _activeRuns.remove(peerId);
    _globalBudgetTimers.remove(peerId)?.cancel();
    final timeline = _timelines[peerId];
    if (timeline == null) {
      return;
    }
    _emit(timeline.copyWith(canCancel: false, canRetry: canRetry));
  }

  bool _isCurrentToken(String peerId, ConnectionRunToken token) {
    return _activeRuns[peerId] == token && !token.isCanceled;
  }

  ConnectionTimeline _ensureLayerRunning(
    ConnectionTimeline timeline,
    ConnectionLayer layer,
  ) {
    final lastStep = timeline.steps.isEmpty ? null : timeline.steps.last;
    if (lastStep?.layer == layer &&
        lastStep?.state == ConnectionStepState.running) {
      return timeline;
    }
    var updated = timeline.addStep(
      ConnectionAttemptStep.pending(
        layer: layer,
        userMessage: _runningMessageFor(layer),
        startedAt: _now(),
      ),
    );
    _emit(updated);
    updated = _replaceLastStep(
      updated,
      updated.steps.last.copyWith(state: ConnectionStepState.running),
    ).copyWith(activeLayer: layer, canCancel: true);
    _emit(updated);
    return updated;
  }

  bool _shouldOfferFallback(ConnectionTimeline timeline) {
    return timeline.policy.mode != ConnectionMode.auto &&
        timeline.shouldShowFallbackPrompt;
  }

  ConnectionPolicy _policyForFallbackChoice(ConnectionFallbackChoice choice) {
    return switch (choice) {
      ConnectionFallbackChoice.tryAuto => const ConnectionPolicy(
        mode: ConnectionMode.auto,
      ),
      ConnectionFallbackChoice.tryRelay => const ConnectionPolicy(
        mode: ConnectionMode.webRtcRelayOnly,
      ),
      ConnectionFallbackChoice.tryIroh => const ConnectionPolicy(
        mode: ConnectionMode.irohFallback,
      ),
      ConnectionFallbackChoice.cancel => const ConnectionPolicy.defaults(),
    };
  }

  ConnectionFailureCode _failureForCancelReason(ConnectionCancelReason reason) {
    return switch (reason) {
      ConnectionCancelReason.globalBudgetExceeded =>
        ConnectionFailureCode.globalBudgetExceeded,
      ConnectionCancelReason.userCanceled => ConnectionFailureCode.userCanceled,
      _ => ConnectionFailureCode.userCanceled,
    };
  }

  Duration _timeoutForLayer(ConnectionLayer layer) {
    return switch (layer) {
      ConnectionLayer.preflight => _timeouts.webRtcDirect,
      ConnectionLayer.webRtcDirect => _timeouts.webRtcDirect,
      ConnectionLayer.webRtcPrimaryRelay => _timeouts.webRtcPrimaryRelay,
      ConnectionLayer.webRtcBackupRelay => _timeouts.webRtcBackupRelay,
      ConnectionLayer.webRtcFullRestart => _timeouts.webRtcFullRestart,
      ConnectionLayer.iroh => _timeouts.iroh,
    };
  }

  Duration _retryDelay() {
    if (_timeouts.retryMaxJitter == Duration.zero) {
      return _timeouts.retryBaseDelay;
    }
    final random = Random();
    final jitter = random.nextInt(_timeouts.retryMaxJitter.inMilliseconds + 1);
    return _timeouts.retryBaseDelay + Duration(milliseconds: jitter);
  }

  String _runningMessageFor(ConnectionLayer layer) {
    return switch (layer) {
      ConnectionLayer.preflight => 'Checking peer.',
      ConnectionLayer.webRtcDirect => 'Trying direct peer route.',
      ConnectionLayer.webRtcPrimaryRelay => 'Trying primary TURN relay.',
      ConnectionLayer.webRtcBackupRelay => 'Trying backup TURN relay.',
      ConnectionLayer.webRtcFullRestart => 'Restarting connection route.',
      ConnectionLayer.iroh => 'Trying Iroh fallback.',
    };
  }

  StreamController<ConnectionTimeline> _controllerFor(String peerId) {
    return _timelineControllers.putIfAbsent(
      peerId,
      () => StreamController<ConnectionTimeline>.broadcast(sync: true),
    );
  }

  ConnectionTimeline _replaceLastStep(
    ConnectionTimeline timeline,
    ConnectionAttemptStep step,
  ) {
    final steps = <ConnectionAttemptStep>[...timeline.steps];
    final fullHistory = <ConnectionAttemptStep>[...timeline.fullHistory];
    if (steps.isNotEmpty) {
      steps[steps.length - 1] = step;
    }
    if (fullHistory.isNotEmpty) {
      fullHistory[fullHistory.length - 1] = step;
    }
    return timeline.copyWith(steps: steps, fullHistory: fullHistory);
  }
}
