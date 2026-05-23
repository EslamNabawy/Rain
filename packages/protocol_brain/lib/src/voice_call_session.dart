import 'dart:async';

import 'package:peer_core/peer_core.dart';

import 'voice_call_frame.dart';

typedef VoiceCallFrameSender = FutureOr<void> Function(VoiceCallFrame frame);
typedef VoiceCallClock = DateTime Function();
typedef VoiceCallLogSink = void Function(String message);

const String _voiceCallFailedReasonCode = 'failed';
const String _voiceCallBusyReasonCode = 'busy';
const String _voiceCallRejectedReasonCode = 'rejected';
const String _voiceCallSignalingFailedReasonCode = 'signalingFailed';
const String _voiceCallRingingTimeoutReasonCode = 'ringingTimeout';
const String _voiceCallIceTimeoutReasonCode = 'iceTimeout';
const String _voiceCallMicrophoneDeniedReasonCode = 'microphoneDenied';

enum VoiceCallSessionPhase {
  idle,
  preflightingMic,
  outgoingRinging,
  incomingRinging,
  creatingMedia,
  connectingMedia,
  active,
  ending,
  failed,
}

final class VoiceCallSessionTimeouts {
  const VoiceCallSessionTimeouts({
    this.ringing = const Duration(seconds: 45),
    this.answer = const Duration(seconds: 15),
    this.media = const Duration(seconds: 20),
    this.cleanup = const Duration(seconds: 5),
  });

  final Duration ringing;
  final Duration answer;
  final Duration media;
  final Duration cleanup;
}

final class VoiceCallSessionState {
  const VoiceCallSessionState({
    required this.phase,
    required this.updatedAt,
    this.audioLevel = const VoiceMediaAudioLevel.unavailable(),
    this.detail,
    this.error,
    this.reasonCode,
    this.mediaDiagnostics,
  });

  factory VoiceCallSessionState.idle({required int updatedAt}) {
    return VoiceCallSessionState(
      phase: VoiceCallSessionPhase.idle,
      updatedAt: updatedAt,
      detail: 'Idle',
    );
  }

  final VoiceCallSessionPhase phase;
  final int updatedAt;
  final VoiceMediaAudioLevel audioLevel;
  final String? detail;
  final Object? error;
  final String? reasonCode;
  final VoiceMediaDiagnostics? mediaDiagnostics;
}

final class VoiceCallSession {
  VoiceCallSession({
    required this.localPeerId,
    required this.remotePeerId,
    required this.callId,
    required this.sessionEpoch,
    required this.media,
    required this.sendFrame,
    this.timeouts = const VoiceCallSessionTimeouts(),
    this.clock = DateTime.now,
    this.logger,
    bool? isOfferOwner,
  }) : state = VoiceCallSessionState.idle(
         updatedAt: clock().millisecondsSinceEpoch,
       ),
       _isOfferOwnerOverride = isOfferOwner {
    if (sessionEpoch <= 0) {
      throw ArgumentError.value(
        sessionEpoch,
        'sessionEpoch',
        'Session epoch must be positive.',
      );
    }
    _normalizedLocalPeerId = _normalizePeerId(localPeerId);
    _normalizedRemotePeerId = _normalizePeerId(remotePeerId);
    _iceSubscription = media.onIceCandidate.listen(_handleLocalCandidate);
    _mediaStateSubscription = media.onStateChanged.listen(_handleMediaState);
    _audioLevelSubscription = media.onAudioLevelChanged.listen(
      _handleAudioLevel,
    );
  }

  final String localPeerId;
  final String remotePeerId;
  final String callId;
  final int sessionEpoch;
  final VoiceMediaConnection media;
  final VoiceCallFrameSender sendFrame;
  final VoiceCallSessionTimeouts timeouts;
  final VoiceCallClock clock;
  final VoiceCallLogSink? logger;
  final bool? _isOfferOwnerOverride;

  late final String _normalizedLocalPeerId;
  late final String _normalizedRemotePeerId;
  late final StreamSubscription<VoiceIceCandidate> _iceSubscription;
  late final StreamSubscription<VoiceMediaState> _mediaStateSubscription;
  late final StreamSubscription<VoiceMediaAudioLevel> _audioLevelSubscription;
  final StreamController<VoiceCallSessionState> _stateController =
      StreamController<VoiceCallSessionState>.broadcast(sync: true);

  VoiceCallSessionState state;
  Timer? _ringingTimer;
  Timer? _answerTimer;
  Timer? _mediaTimer;
  int _lastReceivedOrderedSeq = 0;
  int _lastSentSeq = 0;
  final Set<String> _receivedCandidateKeys = <String>{};
  bool _negotiatingMedia = false;
  bool _disposed = false;
  Future<void> _operationTail = Future<void>.value();

  bool get isOfferOwner =>
      _isOfferOwnerOverride ?? isVoiceCallOfferOwner(localPeerId, remotePeerId);

  Stream<VoiceCallSessionState> get onStateChanged => _stateController.stream;

  Future<void> startOutgoing() {
    return _enqueue(() async {
      if (!_transitionTo(
        VoiceCallSessionPhase.preflightingMic,
        detail: 'Checking microphone permission.',
      )) {
        return;
      }
      try {
        await media.startLocalAudio();
      } catch (error) {
        await _fail('Microphone permission required.', error: error);
        rethrow;
      }
      if (!_transitionTo(
        VoiceCallSessionPhase.outgoingRinging,
        detail: 'Ringing @$remotePeerId.',
      )) {
        return;
      }
      _armRingingTimeout();
      try {
        await _send(VoiceCallFrameType.invite);
      } catch (error) {
        await _fail(
          'Voice call signaling failed.',
          error: error,
          reasonCode: _voiceCallSignalingFailedReasonCode,
        );
        rethrow;
      }
    });
  }

  Future<void> acceptIncoming() {
    return _enqueue(() async {
      if (state.phase != VoiceCallSessionPhase.incomingRinging) {
        _logInvalidEvent('acceptIncoming');
        return;
      }
      _clearRingingTimeout();
      if (!_transitionTo(
        VoiceCallSessionPhase.preflightingMic,
        detail: 'Checking microphone permission.',
      )) {
        return;
      }
      try {
        await media.startLocalAudio();
      } catch (error) {
        await _send(
          VoiceCallFrameType.reject,
          reason: 'Microphone permission required.',
          reasonCode: _voiceCallMicrophoneDeniedReasonCode,
          bestEffort: true,
        );
        await _fail('Microphone permission required.', error: error);
        rethrow;
      }
      if (!_transitionTo(
        VoiceCallSessionPhase.connectingMedia,
        detail: isOfferOwner
            ? 'Creating voice media offer.'
            : 'Waiting for voice media offer.',
      )) {
        return;
      }
      try {
        await _send(VoiceCallFrameType.accept);
        if (isOfferOwner) {
          await _createAndSendOffer();
        } else {
          _armAnswerTimeout('Timed out waiting for voice media offer.');
        }
      } catch (error) {
        await _fail(
          'Voice call signaling failed.',
          error: error,
          notifyPeer: true,
          reasonCode: _voiceCallSignalingFailedReasonCode,
        );
        rethrow;
      }
    });
  }

  Future<void> rejectIncoming({String reason = 'Rejected.'}) {
    return _enqueue(() async {
      if (state.phase != VoiceCallSessionPhase.incomingRinging) {
        return;
      }
      await _send(
        VoiceCallFrameType.reject,
        reason: reason,
        reasonCode: _voiceCallRejectedReasonCode,
        bestEffort: true,
      );
      await _clearVoiceOnly(detail: reason);
    });
  }

  Future<void> handleFrame(VoiceCallFrame frame) {
    return _enqueue(() => _handleFrame(frame));
  }

  Future<void> hangUp({String reason = 'Call ended.'}) {
    return _enqueue(() async {
      if (state.phase == VoiceCallSessionPhase.idle ||
          state.phase == VoiceCallSessionPhase.failed) {
        return;
      }
      await _send(VoiceCallFrameType.hangup, reason: reason, bestEffort: true);
      await _clearVoiceOnly(detail: reason);
    });
  }

  Future<void> setMuted({required bool muted}) {
    return _enqueue(() async {
      if (state.phase != VoiceCallSessionPhase.active) {
        _logInvalidEvent('mute in ${state.phase.name}');
        return;
      }
      await media.setMuted(muted: muted);
      await _send(VoiceCallFrameType.mute, muted: muted, bestEffort: true);
    });
  }

  Future<void> setDeafened({required bool deafened}) {
    return _enqueue(() async {
      if (state.phase != VoiceCallSessionPhase.active) {
        _logInvalidEvent('deafen in ${state.phase.name}');
        return;
      }
      await media.setDeafened(deafened: deafened);
    });
  }

  Future<void> setAudioOutputRoute(VoiceMediaOutputRoute route) {
    return _enqueue(() async {
      if (state.phase != VoiceCallSessionPhase.active) {
        _logInvalidEvent('audio output route in ${state.phase.name}');
        return;
      }
      await media.setAudioOutputRoute(route);
    });
  }

  Future<void> dispose() {
    return _enqueue(() async {
      if (_disposed) {
        return;
      }
      _disposed = true;
      _clearTimers();
      await _iceSubscription.cancel();
      await _mediaStateSubscription.cancel();
      await _audioLevelSubscription.cancel();
      await _disposeMedia();
      await _stateController.close();
    });
  }

  Future<void> _handleFrame(VoiceCallFrame frame) async {
    if (!_acceptFrame(frame)) {
      return;
    }

    switch (frame.type) {
      case VoiceCallFrameType.invite:
        await _handleInvite(frame);
        break;
      case VoiceCallFrameType.accept:
        await _handleAccept(frame);
        break;
      case VoiceCallFrameType.reject:
      case VoiceCallFrameType.busy:
        await _handleRejected(frame);
        break;
      case VoiceCallFrameType.offer:
        await _handleOffer(frame);
        break;
      case VoiceCallFrameType.answer:
        await _handleAnswer(frame);
        break;
      case VoiceCallFrameType.candidate:
        await _handleRemoteCandidate(frame);
        break;
      case VoiceCallFrameType.hangup:
        if (frame.reasonCode != null) {
          await _fail(
            frame.reason ?? 'Voice call media could not connect.',
            reasonCode: frame.reasonCode,
          );
        } else {
          await _clearVoiceOnly(detail: frame.reason ?? 'Peer ended the call.');
        }
        break;
      case VoiceCallFrameType.mute:
        break;
    }
  }

  Future<void> _handleInvite(VoiceCallFrame frame) async {
    if (state.phase == VoiceCallSessionPhase.idle ||
        state.phase == VoiceCallSessionPhase.failed) {
      _clearTimers();
      if (_transitionTo(
        VoiceCallSessionPhase.incomingRinging,
        detail: '@${frame.from} is calling.',
      )) {
        _armRingingTimeout();
      }
      return;
    }

    if (state.phase == VoiceCallSessionPhase.incomingRinging) {
      _armRingingTimeout();
      return;
    }

    await _send(VoiceCallFrameType.busy, reason: 'Busy.', bestEffort: true);
  }

  Future<void> _handleAccept(VoiceCallFrame frame) async {
    if (state.phase != VoiceCallSessionPhase.outgoingRinging) {
      _logInvalidEvent('accept frame in ${state.phase.name}');
      return;
    }
    _clearRingingTimeout();
    if (!_transitionTo(
      VoiceCallSessionPhase.connectingMedia,
      detail: isOfferOwner
          ? 'Creating voice media offer.'
          : 'Waiting for voice media offer.',
    )) {
      return;
    }
    if (isOfferOwner) {
      await _createAndSendOffer();
    } else {
      _armAnswerTimeout('Timed out waiting for voice media offer.');
    }
  }

  Future<void> _handleRejected(VoiceCallFrame frame) async {
    final detail = frame.type == VoiceCallFrameType.busy
        ? 'Peer is busy.'
        : frame.reasonCode == _voiceCallMicrophoneDeniedReasonCode
        ? 'Peer microphone permission required.'
        : frame.reasonCode == _voiceCallRejectedReasonCode ||
              frame.reason == 'Rejected.'
        ? 'Call declined.'
        : frame.reason ?? 'Call declined.';
    await _fail(
      detail,
      reasonCode:
          frame.reasonCode ??
          (frame.type == VoiceCallFrameType.busy
              ? _voiceCallBusyReasonCode
              : _voiceCallRejectedReasonCode),
    );
  }

  Future<void> _handleOffer(VoiceCallFrame frame) async {
    if (isOfferOwner) {
      _logInvalidEvent('remote offer from non-owner');
      return;
    }
    if (state.phase != VoiceCallSessionPhase.connectingMedia ||
        frame.sdp == null ||
        frame.sdpType != 'offer') {
      _logInvalidEvent('offer frame in ${state.phase.name}');
      return;
    }
    await _runMediaNegotiation(() async {
      _clearAnswerTimeout();
      _transitionTo(
        VoiceCallSessionPhase.creatingMedia,
        detail: 'Answering voice media offer.',
      );
      try {
        final answer = await media.acceptOffer(
          VoiceSessionDescription(sdp: frame.sdp!, type: frame.sdpType!),
        );
        _transitionTo(
          VoiceCallSessionPhase.connectingMedia,
          detail: 'Waiting for voice media connection.',
        );
        await _send(
          VoiceCallFrameType.answer,
          sdp: answer.sdp,
          sdpType: answer.type,
        );
        _armMediaTimeout();
      } catch (error) {
        await _sendFailedHangup(error);
        await _fail(
          'Voice call media could not connect.',
          error: error,
          reasonCode: _voiceCallFailedReasonCode,
        );
      }
    });
  }

  Future<void> _handleAnswer(VoiceCallFrame frame) async {
    if (!isOfferOwner) {
      _logInvalidEvent('remote answer for non-owner');
      return;
    }
    if (state.phase != VoiceCallSessionPhase.connectingMedia ||
        frame.sdp == null ||
        frame.sdpType != 'answer') {
      _logInvalidEvent('answer frame in ${state.phase.name}');
      return;
    }
    await _runMediaNegotiation(() async {
      _clearAnswerTimeout();
      try {
        await media.applyAnswer(
          VoiceSessionDescription(sdp: frame.sdp!, type: frame.sdpType!),
        );
        _transitionTo(
          VoiceCallSessionPhase.connectingMedia,
          detail: 'Waiting for voice media connection.',
        );
        _armMediaTimeout();
      } catch (error) {
        await _sendFailedHangup(error);
        await _fail(
          'Voice call media could not connect.',
          error: error,
          reasonCode: _voiceCallFailedReasonCode,
        );
      }
    });
  }

  Future<void> _handleRemoteCandidate(VoiceCallFrame frame) async {
    final candidate = frame.candidate;
    final sdpMid = frame.sdpMid;
    final sdpMLineIndex = frame.sdpMLineIndex;
    if (candidate == null || sdpMid == null || sdpMLineIndex == null) {
      return;
    }
    if (state.phase != VoiceCallSessionPhase.creatingMedia &&
        state.phase != VoiceCallSessionPhase.connectingMedia &&
        state.phase != VoiceCallSessionPhase.active) {
      return;
    }
    try {
      await media.addRemoteCandidate(
        VoiceIceCandidate(
          candidate: candidate,
          sdpMid: sdpMid,
          sdpMLineIndex: sdpMLineIndex,
        ),
      );
    } catch (error) {
      await _sendFailedHangup(error);
      await _fail('Voice call media could not connect.', error: error);
    }
  }

  Future<void> _createAndSendOffer() async {
    await _runMediaNegotiation(() async {
      if (!_transitionTo(
        VoiceCallSessionPhase.creatingMedia,
        detail: 'Creating voice media offer.',
      )) {
        return;
      }
      try {
        final offer = await media.createOffer();
        _transitionTo(
          VoiceCallSessionPhase.connectingMedia,
          detail: 'Waiting for voice media answer.',
        );
        await _send(
          VoiceCallFrameType.offer,
          sdp: offer.sdp,
          sdpType: offer.type,
        );
        _armAnswerTimeout('Timed out waiting for voice media answer.');
      } catch (error) {
        await _sendFailedHangup(error);
        await _fail(
          'Voice call media could not connect.',
          error: error,
          reasonCode: _voiceCallFailedReasonCode,
        );
      }
    });
  }

  void _handleLocalCandidate(VoiceIceCandidate candidate) {
    if (_disposed ||
        candidate.candidate.trim().isEmpty ||
        candidate.sdpMid == null ||
        candidate.sdpMLineIndex == null) {
      return;
    }
    if (state.phase != VoiceCallSessionPhase.creatingMedia &&
        state.phase != VoiceCallSessionPhase.connectingMedia &&
        state.phase != VoiceCallSessionPhase.active) {
      return;
    }
    unawaited(
      _send(
        VoiceCallFrameType.candidate,
        candidate: candidate.candidate,
        sdpMid: candidate.sdpMid,
        sdpMLineIndex: candidate.sdpMLineIndex,
        bestEffort: true,
      ),
    );
  }

  void _handleMediaState(VoiceMediaState mediaState) {
    if (_disposed) {
      return;
    }
    switch (mediaState.phase) {
      case VoiceMediaPhase.connected:
        unawaited(
          _enqueue(() async {
            _clearMediaTimeout();
            if (state.phase == VoiceCallSessionPhase.connectingMedia ||
                state.phase == VoiceCallSessionPhase.creatingMedia) {
              _transitionTo(
                VoiceCallSessionPhase.active,
                detail: 'Voice call connected.',
              );
            }
          }),
        );
        break;
      case VoiceMediaPhase.failed:
        unawaited(
          _enqueue(
            () => _fail(
              'Voice call media could not connect.',
              error: mediaState.error ?? mediaState.detail,
              notifyPeer: true,
              reasonCode: _voiceCallFailedReasonCode,
            ),
          ),
        );
        break;
      case VoiceMediaPhase.idle:
      case VoiceMediaPhase.startingLocalAudio:
      case VoiceMediaPhase.localAudioReady:
      case VoiceMediaPhase.creatingOffer:
      case VoiceMediaPhase.applyingOffer:
      case VoiceMediaPhase.applyingAnswer:
      case VoiceMediaPhase.connecting:
      case VoiceMediaPhase.disposed:
        break;
    }
  }

  void _handleAudioLevel(VoiceMediaAudioLevel audioLevel) {
    if (_disposed ||
        state.phase == VoiceCallSessionPhase.idle ||
        state.phase == VoiceCallSessionPhase.ending ||
        state.phase == VoiceCallSessionPhase.failed) {
      return;
    }
    final updated = VoiceCallSessionState(
      phase: state.phase,
      updatedAt: audioLevel.updatedAt ?? clock().millisecondsSinceEpoch,
      audioLevel: audioLevel,
      detail: state.detail,
      error: state.error,
      reasonCode: state.reasonCode,
      mediaDiagnostics: state.mediaDiagnostics,
    );
    state = updated;
    if (!_stateController.isClosed) {
      _stateController.add(updated);
    }
  }

  bool _acceptFrame(VoiceCallFrame frame) {
    if (_disposed ||
        frame.callId != callId ||
        frame.sessionEpoch != sessionEpoch ||
        _normalizePeerId(frame.from) != _normalizedRemotePeerId ||
        _normalizePeerId(frame.to) != _normalizedLocalPeerId) {
      return false;
    }

    if (frame.type == VoiceCallFrameType.candidate) {
      return _acceptCandidateFrame(frame);
    }

    if (frame.seq <= _lastReceivedOrderedSeq) {
      _logInvalidEvent('stale ${frame.type.name} frame seq=${frame.seq}');
      return false;
    }
    _lastReceivedOrderedSeq = frame.seq;
    return true;
  }

  bool _acceptCandidateFrame(VoiceCallFrame frame) {
    final key = _candidateFrameKey(frame);
    if (key == null) {
      return true;
    }
    if (!_receivedCandidateKeys.add(key)) {
      _logInvalidEvent('duplicate candidate frame seq=${frame.seq}');
      return false;
    }
    return true;
  }

  String? _candidateFrameKey(VoiceCallFrame frame) {
    final candidate = frame.candidate;
    final sdpMid = frame.sdpMid;
    final sdpMLineIndex = frame.sdpMLineIndex;
    if (candidate == null || sdpMid == null || sdpMLineIndex == null) {
      return null;
    }
    return '$sdpMid|$sdpMLineIndex|$candidate';
  }

  Future<void> _send(
    VoiceCallFrameType type, {
    String? reason,
    String? reasonCode,
    bool? muted,
    String? sdp,
    String? sdpType,
    String? candidate,
    String? sdpMid,
    int? sdpMLineIndex,
    bool bestEffort = false,
  }) async {
    final frame = VoiceCallFrame(
      type: type,
      callId: callId,
      from: _normalizedLocalPeerId,
      to: _normalizedRemotePeerId,
      sentAt: clock().millisecondsSinceEpoch,
      seq: _nextSeq(),
      sessionEpoch: sessionEpoch,
      reason: reason,
      reasonCode: reasonCode,
      muted: muted,
      sdp: sdp,
      sdpType: sdpType,
      candidate: candidate,
      sdpMid: sdpMid,
      sdpMLineIndex: sdpMLineIndex,
    );
    try {
      await Future<void>.sync(() => sendFrame(frame));
    } catch (error) {
      if (!bestEffort) {
        rethrow;
      }
      _logInvalidEvent('failed to send ${type.name}: $error');
    }
  }

  int _nextSeq() {
    _lastSentSeq += 1;
    return _lastSentSeq;
  }

  Future<void> _sendFailedHangup(Object error) {
    return _send(
      VoiceCallFrameType.hangup,
      reason: 'Voice call media could not connect.',
      reasonCode: _voiceCallFailedReasonCode,
      bestEffort: true,
    );
  }

  Future<void> _fail(
    String detail, {
    Object? error,
    bool notifyPeer = false,
    String? reasonCode,
  }) async {
    _clearTimers();
    final effectiveReasonCode =
        reasonCode ?? (notifyPeer ? _voiceCallFailedReasonCode : null);
    final mediaDiagnostics = media.diagnostics;
    if (notifyPeer) {
      await _send(
        VoiceCallFrameType.hangup,
        reason: detail,
        reasonCode: effectiveReasonCode,
        bestEffort: true,
      );
    }
    _transitionTo(
      VoiceCallSessionPhase.failed,
      detail: detail,
      error: error,
      reasonCode: effectiveReasonCode,
      mediaDiagnostics: mediaDiagnostics,
    );
    await _disposeMedia();
  }

  Future<void> _clearVoiceOnly({required String detail}) async {
    _clearTimers();
    if (!_transitionTo(VoiceCallSessionPhase.ending, detail: detail)) {
      return;
    }
    await _disposeMedia();
    _transitionTo(VoiceCallSessionPhase.idle, detail: detail);
  }

  Future<void> _disposeMedia() async {
    try {
      await media.dispose().timeout(timeouts.cleanup, onTimeout: () {});
    } catch (error) {
      _logInvalidEvent('media cleanup failed: $error');
    }
  }

  Future<void> _runMediaNegotiation(Future<void> Function() action) async {
    if (_negotiatingMedia) {
      _logInvalidEvent('media negotiation already running');
      return;
    }
    _negotiatingMedia = true;
    try {
      await action();
    } finally {
      _negotiatingMedia = false;
    }
  }

  bool _transitionTo(
    VoiceCallSessionPhase next, {
    String? detail,
    Object? error,
    String? reasonCode,
    VoiceMediaDiagnostics? mediaDiagnostics,
  }) {
    if (!_isAllowedTransition(state.phase, next)) {
      _logInvalidEvent('invalid transition ${state.phase.name} -> $next');
      return false;
    }
    final updated = VoiceCallSessionState(
      phase: next,
      audioLevel: _phaseCanHoldAudioLevel(next)
          ? state.audioLevel
          : const VoiceMediaAudioLevel.unavailable(),
      detail: detail,
      error: error,
      reasonCode: reasonCode,
      mediaDiagnostics: mediaDiagnostics,
      updatedAt: clock().millisecondsSinceEpoch,
    );
    state = updated;
    if (!_stateController.isClosed) {
      _stateController.add(updated);
    }
    return true;
  }

  bool _phaseCanHoldAudioLevel(VoiceCallSessionPhase phase) {
    return phase == VoiceCallSessionPhase.creatingMedia ||
        phase == VoiceCallSessionPhase.connectingMedia ||
        phase == VoiceCallSessionPhase.active;
  }

  bool _isAllowedTransition(
    VoiceCallSessionPhase current,
    VoiceCallSessionPhase next,
  ) {
    if (current == next) {
      return true;
    }
    return switch (current) {
      VoiceCallSessionPhase.idle =>
        next == VoiceCallSessionPhase.preflightingMic ||
            next == VoiceCallSessionPhase.incomingRinging ||
            next == VoiceCallSessionPhase.failed,
      VoiceCallSessionPhase.preflightingMic =>
        next == VoiceCallSessionPhase.outgoingRinging ||
            next == VoiceCallSessionPhase.connectingMedia ||
            next == VoiceCallSessionPhase.failed ||
            next == VoiceCallSessionPhase.ending,
      VoiceCallSessionPhase.outgoingRinging =>
        next == VoiceCallSessionPhase.creatingMedia ||
            next == VoiceCallSessionPhase.connectingMedia ||
            next == VoiceCallSessionPhase.failed ||
            next == VoiceCallSessionPhase.ending,
      VoiceCallSessionPhase.incomingRinging =>
        next == VoiceCallSessionPhase.preflightingMic ||
            next == VoiceCallSessionPhase.failed ||
            next == VoiceCallSessionPhase.ending ||
            next == VoiceCallSessionPhase.idle,
      VoiceCallSessionPhase.creatingMedia =>
        next == VoiceCallSessionPhase.connectingMedia ||
            next == VoiceCallSessionPhase.failed ||
            next == VoiceCallSessionPhase.ending,
      VoiceCallSessionPhase.connectingMedia =>
        next == VoiceCallSessionPhase.creatingMedia ||
            next == VoiceCallSessionPhase.active ||
            next == VoiceCallSessionPhase.failed ||
            next == VoiceCallSessionPhase.ending,
      VoiceCallSessionPhase.active =>
        next == VoiceCallSessionPhase.ending ||
            next == VoiceCallSessionPhase.failed,
      VoiceCallSessionPhase.ending =>
        next == VoiceCallSessionPhase.idle ||
            next == VoiceCallSessionPhase.failed,
      VoiceCallSessionPhase.failed => next == VoiceCallSessionPhase.idle,
    };
  }

  void _armRingingTimeout() {
    _clearRingingTimeout();
    _ringingTimer = Timer(timeouts.ringing, () {
      unawaited(
        _enqueue(
          () => _fail(
            'Call timed out while ringing.',
            reasonCode: _voiceCallRingingTimeoutReasonCode,
          ),
        ),
      );
    });
  }

  void _armAnswerTimeout(String detail) {
    _clearAnswerTimeout();
    _answerTimer = Timer(timeouts.answer, () {
      unawaited(_enqueue(() => _fail(detail, notifyPeer: true)));
    });
  }

  void _armMediaTimeout() {
    _clearMediaTimeout();
    _mediaTimer = Timer(timeouts.media, () {
      unawaited(
        _enqueue(
          () => _fail(
            'Call media could not connect: ICE timeout.',
            notifyPeer: true,
            reasonCode: _voiceCallIceTimeoutReasonCode,
          ),
        ),
      );
    });
  }

  void _clearTimers() {
    _clearRingingTimeout();
    _clearAnswerTimeout();
    _clearMediaTimeout();
  }

  void _clearRingingTimeout() {
    _ringingTimer?.cancel();
    _ringingTimer = null;
  }

  void _clearAnswerTimeout() {
    _answerTimer?.cancel();
    _answerTimer = null;
  }

  void _clearMediaTimeout() {
    _mediaTimer?.cancel();
    _mediaTimer = null;
  }

  Future<void> _enqueue(Future<void> Function() action) {
    final current = _operationTail.then((_) => action());
    _operationTail = current.catchError((_) {});
    return current;
  }

  void _logInvalidEvent(String message) {
    logger?.call(message);
  }
}

bool isVoiceCallOfferOwner(String localPeerId, String remotePeerId) {
  return _normalizePeerId(
        localPeerId,
      ).compareTo(_normalizePeerId(remotePeerId)) <=
      0;
}

String _normalizePeerId(String value) => value.trim().toLowerCase();
