import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';
import 'package:protocol_brain/protocol_brain.dart';
import 'package:rain_core/rain_core.dart';

import 'package:rain/presentation/navigation/app_routes.dart';
import 'package:rain/application/audio/rain_sound_event.dart';
import 'package:rain/application/runtime/media_device_settings.dart';
import 'package:rain/application/runtime/video_call_renderers.dart';
import 'package:rain/application/runtime/voice_call_state.dart';
import 'package:rain/application/state/app_providers.dart';
import 'package:rain/application/state/connection_diagnostics.dart';
import 'package:rain/application/state/file_transfer_view.dart';
import 'package:rain/application/runtime/rain_runtime_controller.dart';
import 'package:rain/application/state/sound_event_providers.dart';
import 'package:rain/infrastructure/services/app_settings_store.dart';
import 'package:rain/presentation/branding/rain_peer_core_mark.dart';
import 'package:rain/presentation/branding/rain_ripple_halo_surface.dart';
import 'package:rain/presentation/branding/rain_state_surfaces.dart';
import 'package:rain/presentation/theme/rain_theme.dart';
import 'package:rain/presentation/widgets/app_components.dart';
import 'package:rain/presentation/widgets/chat_composer.dart';
import 'package:rain/presentation/widgets/app_dialogs.dart';
import 'package:rain/presentation/widgets/calls/rain_call_controls.dart';
import 'package:rain/presentation/widgets/calls/rain_call_manager_bar.dart';
import 'package:rain/presentation/widgets/calls/rain_call_overlay.dart';
import 'package:rain/presentation/widgets/rain_chat_widgets.dart';

part '../widgets/home/shell_header.dart';
part '../widgets/home/link_status.dart';
part '../widgets/home/friends_list.dart';
part '../widgets/home/chat_panel.dart';
part '../widgets/home/file_transfer_bubble.dart';

String _formatUiError(Object error) {
  final raw = error.toString().trim();
  const prefixes = <String>['Exception: ', 'Bad state: ', 'StateError: '];
  var message = raw;
  for (final prefix in prefixes) {
    if (raw.startsWith(prefix)) {
      message = raw.substring(prefix.length).trim();
      break;
    }
  }
  final normalized = message.toLowerCase();
  if (normalized.contains('active file transfer')) {
    return 'Finish the active file transfer first.';
  }
  if (normalized.contains('finish the call before') ||
      normalized == 'finish the call first.') {
    return 'Finish the call before sending files.';
  }
  if (normalized.contains('microphone') &&
      (normalized.contains('permission') || normalized.contains('denied'))) {
    return 'Microphone permission required.';
  }
  if (normalized.contains('peer is busy') ||
      normalized == 'busy.' ||
      normalized.contains('active voice call already exists') ||
      normalized.contains('activevoicepairs') ||
      normalized.contains('active voice pair')) {
    return 'Peer is busy.';
  }
  if (normalized == 'rejected.' ||
      normalized.contains('call declined') ||
      normalized.contains('call rejected')) {
    return 'Call declined.';
  }
  if (normalized.contains('network connection lost') ||
      normalized.contains('network lost') ||
      normalized.contains('internet connection') ||
      normalized.contains('network is unavailable') ||
      normalized.contains('network unavailable')) {
    return 'Network connection lost. Call ended.';
  }
  if (normalized.contains('timed out') ||
      normalized.contains('voice call expired') ||
      normalized.contains('call room expired')) {
    return 'Call timed out.';
  }
  if (normalized.contains('voice signaling') ||
      normalized.contains('firebase') ||
      normalized.contains('unknown voice call') ||
      normalized.contains('voice call already exists') ||
      normalized.contains('already ended') ||
      normalized.contains('permission-denied') ||
      normalized.contains('database')) {
    return 'Call setup failed. Try again.';
  }
  if (normalized.contains('ice timeout')) {
    return 'Call media could not connect. Try again.';
  }
  if (normalized.contains('no remote audio')) {
    return 'Call media could not connect. Try again.';
  }
  if (normalized.contains('rtcrtptransceiver') ||
      normalized.contains('setdirection') ||
      normalized.contains('setremotedescription') ||
      normalized.contains('peerconnectionsetremotedescription') ||
      normalized.contains('m-line') ||
      normalized.contains('peer connection changed while')) {
    return 'Call media could not connect. Try again.';
  }
  return message;
}

VoiceCallOutputRoute _voiceCallOutputRouteForPreference(
  CallAudioOutputPreference preference,
) {
  return switch (preference) {
    CallAudioOutputPreference.systemDefault =>
      VoiceCallOutputRoute.systemDefault,
    CallAudioOutputPreference.speaker => VoiceCallOutputRoute.speaker,
    CallAudioOutputPreference.bluetooth => VoiceCallOutputRoute.bluetooth,
  };
}

RainSoundEvent? rainVoiceCallLifecycleSoundEventFor(
  VoiceCallState? previous,
  VoiceCallState next,
) {
  final call = switch (next.phase) {
    VoiceCallPhase.idle => previous,
    _ => next,
  };
  final callId = call?.callId;
  if (callId == null || callId.trim().isEmpty) {
    return null;
  }
  return switch (next.phase) {
    VoiceCallPhase.incomingRinging => RainSoundEvent.callIncomingStarted(
      callId: callId,
      peerId: next.peerId,
      sessionEpoch: next.sessionEpoch,
      mediaMode: next.mediaMode,
    ),
    VoiceCallPhase.outgoingRinging => RainSoundEvent.callOutgoingStarted(
      callId: callId,
      peerId: next.peerId,
      sessionEpoch: next.sessionEpoch,
      mediaMode: next.mediaMode,
    ),
    VoiceCallPhase.active => RainSoundEvent.callConnected(
      callId: callId,
      peerId: next.peerId,
      sessionEpoch: next.sessionEpoch,
      mediaMode: next.mediaMode,
    ),
    VoiceCallPhase.failed => RainSoundEvent.callFailed(
      callId: callId,
      peerId: next.peerId,
      sessionEpoch: next.sessionEpoch,
      mediaMode: next.mediaMode,
      errorKey: _voiceCallFailureErrorKey(next),
    ),
    VoiceCallPhase.idle
        when previous != null &&
            previous.phase != VoiceCallPhase.idle &&
            previous.phase != VoiceCallPhase.failed =>
      RainSoundEvent.callEnded(
        callId: callId,
        peerId: previous.peerId,
        sessionEpoch: previous.sessionEpoch,
        mediaMode: previous.mediaMode,
      ),
    VoiceCallPhase.idle ||
    VoiceCallPhase.connectingPeer ||
    VoiceCallPhase.connectingMedia ||
    VoiceCallPhase.ending => null,
  };
}

String? rainVoiceCallLifecycleSoundKeyFor(
  VoiceCallState? previous,
  VoiceCallState next,
) {
  final event = rainVoiceCallLifecycleSoundEventFor(previous, next);
  if (event == null || event.callId == null) {
    return null;
  }
  return '${event.callId}|${event.sessionEpoch ?? -1}|${next.phase.name}';
}

String _voiceCallFailureErrorKey(VoiceCallState state) {
  final reason = state.failureReason;
  if (reason != null) {
    return 'voice.${reason.name}';
  }
  return 'voice.call.failed';
}

RainSoundEvent? rainChatReceiveSoundEventFor({
  required List<StoredMessage>? previousMessages,
  required List<StoredMessage>? nextMessages,
  required String conversationId,
}) {
  if (previousMessages == null || nextMessages == null) {
    return null;
  }

  final previousLatestIncoming = _latestIncomingMessageIdForSound(
    previousMessages,
  );
  final nextLatestIncoming = _latestIncomingMessageIdForSound(nextMessages);
  if (nextLatestIncoming == null ||
      nextLatestIncoming == previousLatestIncoming ||
      nextMessages.length < previousMessages.length) {
    return null;
  }
  return RainSoundEvent.chatReceive(conversationId: conversationId);
}

RainSoundEvent rainChatSendSoundEventFor(String conversationId) {
  return RainSoundEvent.chatSend(conversationId: conversationId);
}

RainSoundEvent rainUiActionSoundEvent() {
  return RainSoundEvent.uiAction();
}

RainSoundEvent rainUiWarningSoundEvent(String errorKey) {
  return RainSoundEvent.warning(errorKey: errorKey);
}

String? _latestIncomingMessageIdForSound(List<StoredMessage> messages) {
  for (final message in messages.reversed) {
    if (!message.isOutgoing) {
      return message.id;
    }
  }
  return null;
}

void _dispatchRainSoundEvent(WidgetRef ref, RainSoundEvent event) {
  unawaited(ref.read(soundEventRouterProvider).dispatch(event));
}

void _dispatchVoiceCommandFailureSoundForRef(
  WidgetRef ref,
  Object error, {
  VoiceCallState? before,
}) {
  final current = ref.read(voiceCallProvider);
  final failedCallState = current.phase == VoiceCallPhase.failed
      ? current
      : null;
  if (failedCallState?.callId != null) {
    return;
  }
  final call = _soundEventCallContext(current, fallback: before);
  final callId = call?.callId;
  if (callId == null || callId.trim().isEmpty) {
    _dispatchRainSoundEvent(
      ref,
      RainSoundEvent.warning(errorKey: _voiceCommandErrorKey(error)),
    );
    return;
  }
  _dispatchRainSoundEvent(
    ref,
    RainSoundEvent.callFailed(
      callId: callId,
      peerId: call?.peerId,
      sessionEpoch: call?.sessionEpoch,
      mediaMode: call?.mediaMode ?? CallMediaMode.audio,
      errorKey: _voiceCommandErrorKey(error),
    ),
  );
}

VoiceCallState? _soundEventCallContext(
  VoiceCallState current, {
  VoiceCallState? fallback,
}) {
  if (current.callId != null && current.callId!.trim().isNotEmpty) {
    return current;
  }
  final fallbackCallId = fallback?.callId;
  if (fallbackCallId != null && fallbackCallId.trim().isNotEmpty) {
    return fallback;
  }
  return null;
}

String _voiceCommandErrorKey(Object error) {
  final message = _formatUiError(error).toLowerCase();
  if (message.contains('microphone')) {
    return 'voice.microphone_denied';
  }
  if (message.contains('camera')) {
    return 'voice.camera_denied';
  }
  if (message.contains('busy')) {
    return 'voice.peer_busy';
  }
  if (message.contains('network')) {
    return 'voice.network_lost';
  }
  if (message.contains('media')) {
    return 'voice.media_failed';
  }
  return 'voice.command_failed';
}

RainSoundEvent _callControlMuteEvent(VoiceCallState call) {
  return RainSoundEvent.callControlMute(
    callId: call.callId,
    peerId: call.peerId,
    sessionEpoch: call.sessionEpoch,
    mediaMode: call.mediaMode,
  );
}

RainSoundEvent _callControlUnmuteEvent(VoiceCallState call) {
  return RainSoundEvent.callControlUnmute(
    callId: call.callId,
    peerId: call.peerId,
    sessionEpoch: call.sessionEpoch,
    mediaMode: call.mediaMode,
  );
}

RainSoundEvent _callControlDeafenEvent(VoiceCallState call) {
  return RainSoundEvent.callControlDeafen(
    callId: call.callId,
    peerId: call.peerId,
    sessionEpoch: call.sessionEpoch,
    mediaMode: call.mediaMode,
  );
}

RainSoundEvent _callControlUndeafenEvent(VoiceCallState call) {
  return RainSoundEvent.callControlUndeafen(
    callId: call.callId,
    peerId: call.peerId,
    sessionEpoch: call.sessionEpoch,
    mediaMode: call.mediaMode,
  );
}

RainSoundEvent _callControlCameraMuteEvent(VoiceCallState call) {
  return RainSoundEvent.callControlCameraMute(
    callId: call.callId,
    peerId: call.peerId,
    sessionEpoch: call.sessionEpoch,
    mediaMode: call.mediaMode,
  );
}

RainSoundEvent _callControlCameraUnmuteEvent(VoiceCallState call) {
  return RainSoundEvent.callControlCameraUnmute(
    callId: call.callId,
    peerId: call.peerId,
    sessionEpoch: call.sessionEpoch,
    mediaMode: call.mediaMode,
  );
}

RainSoundEvent _callControlRouteChangedEvent(VoiceCallState call) {
  return RainSoundEvent.callRouteChanged(
    callId: call.callId,
    peerId: call.peerId,
    sessionEpoch: call.sessionEpoch,
    mediaMode: call.mediaMode,
  );
}

String _candidateLabel(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return 'Unknown';
  }
  return trimmed.toUpperCase();
}

String _addressFamilyLabel(PeerAddressFamily family) {
  return switch (family) {
    PeerAddressFamily.ipv4 => 'IPv4',
    PeerAddressFamily.ipv6 => 'IPv6',
    PeerAddressFamily.mixed => 'Mixed',
    PeerAddressFamily.unknown => 'Unknown',
  };
}

String _routeAddressFamilyLabel(PeerConnectionRoute route) {
  final family = route.addressFamily;
  if (family != PeerAddressFamily.mixed) {
    return _addressFamilyLabel(family);
  }
  final local = route.localAddressFamily;
  final remote = route.remoteAddressFamily;
  if (local != PeerAddressFamily.unknown &&
      remote != PeerAddressFamily.unknown) {
    return '${_addressFamilyLabel(local)} / ${_addressFamilyLabel(remote)}';
  }
  return _addressFamilyLabel(family);
}

String _routeAddressFamilySuffix(PeerConnectionRoute route) {
  final label = _routeAddressFamilyLabel(route);
  return label == 'Unknown' ? '' : ' - $label';
}

String _protocolLabel(PeerConnectionRoute route) {
  final protocol = route.protocol?.trim();
  final relayProtocol = route.relayProtocol?.trim();
  if ((protocol == null || protocol.isEmpty) &&
      (relayProtocol == null || relayProtocol.isEmpty)) {
    return 'Unknown';
  }
  final parts = <String>[
    if (protocol != null && protocol.isNotEmpty) protocol.toUpperCase(),
    if (relayProtocol != null && relayProtocol.isNotEmpty)
      'relay ${relayProtocol.toUpperCase()}',
  ];
  return parts.join(' / ');
}

String _phaseLabel(SessionPhase? phase) {
  return switch (phase) {
    SessionPhase.idle => 'Idle',
    SessionPhase.checkingPresence => 'Checking presence',
    SessionPhase.registeringPeer => 'Registering peer',
    SessionPhase.waitingForOffer => 'Waiting for offer',
    SessionPhase.creatingOffer => 'Creating offer',
    SessionPhase.writingOffer => 'Writing offer',
    SessionPhase.waitingForAnswer => 'Waiting for answer',
    SessionPhase.writingAnswer => 'Writing answer',
    SessionPhase.exchangingIce => 'Exchanging ICE',
    SessionPhase.openingDataChannels => 'Opening channels',
    SessionPhase.negotiatingMedia => 'Negotiating media',
    SessionPhase.connected => 'Connected',
    SessionPhase.reconnecting => 'Reconnecting',
    SessionPhase.disconnecting => 'Disconnecting',
    SessionPhase.disconnected => 'Disconnected',
    SessionPhase.failed => 'Failed',
    null => 'None',
  };
}

String _rttLabel(double? rtt) {
  if (rtt == null || rtt.isNaN || rtt.isInfinite) {
    return 'Unknown';
  }
  return '${(rtt * 1000).round()} ms';
}

String _bitrateLabel(double? bitrate) {
  if (bitrate == null || bitrate.isNaN || bitrate.isInfinite || bitrate <= 0) {
    return 'Unknown';
  }
  if (bitrate >= 1000000) {
    return '${(bitrate / 1000000).toStringAsFixed(1)} Mbps';
  }
  return '${(bitrate / 1000).round()} Kbps';
}

String _nextRetryLabel(int? nextRetryAt) {
  if (nextRetryAt == null) {
    return 'None';
  }
  final remaining = nextRetryAt - DateTime.now().millisecondsSinceEpoch;
  if (remaining <= 0) {
    return 'Ready';
  }
  final seconds = (remaining / 1000).ceil();
  if (seconds < 60) {
    return '${seconds}s';
  }
  return '${(seconds / 60).ceil()}m';
}

String _mobileLinkDetail(
  ConnectionDiagnostics diagnostics,
  _ConnectionStatus status,
) {
  if (diagnostics.route.kind == PeerRouteKind.direct) {
    return 'Direct peer route${_routeAddressFamilySuffix(diagnostics.route)}';
  }
  if (diagnostics.route.kind == PeerRouteKind.relay) {
    final protocol = diagnostics.route.relayProtocol?.trim();
    return protocol == null || protocol.isEmpty
        ? 'TURN relay route${_routeAddressFamilySuffix(diagnostics.route)}'
        : 'TURN relay ${protocol.toUpperCase()}${_routeAddressFamilySuffix(diagnostics.route)}';
  }
  if (diagnostics.lastError != null &&
      diagnostics.lastError!.trim().isNotEmpty) {
    return diagnostics.lastError!.trim();
  }
  return status.detail;
}

class _ConnectionStatus {
  const _ConnectionStatus({
    required this.label,
    required this.icon,
    required this.color,
    required this.detail,
    this.isBusy = false,
    this.isConnected = false,
    this.canDisconnect = false,
  });

  final String label;
  final IconData icon;
  final Color color;
  final String detail;
  final bool isBusy;
  final bool isConnected;
  final bool canDisconnect;
}

_ConnectionStatus _connectionStatusForDiagnostics(
  ConnectionDiagnostics diagnostics,
) {
  switch (diagnostics.label) {
    case 'Unavailable':
      return const _ConnectionStatus(
        label: 'Unavailable',
        icon: Icons.lock_outline,
        color: Color(0xFF52646D),
        detail: 'Only accepted friends can chat.',
      );
    case 'Disconnecting':
      return const _ConnectionStatus(
        label: 'Disconnecting',
        icon: Icons.link_off,
        color: Color(0xFFFBBF24),
        detail: 'Closing peer session.',
        isBusy: true,
        canDisconnect: true,
      );
    case 'Disconnected':
      return const _ConnectionStatus(
        label: 'Disconnected',
        icon: Icons.link_off,
        color: Color(0xFF52646D),
        detail: 'Manual disconnect. Press Connect to open the peer lane again.',
      );
    case 'Direct':
      return _ConnectionStatus(
        label: 'Direct',
        icon: Icons.hub_outlined,
        color: const Color(0xFF2DD4A3),
        detail: diagnostics.detail,
        isConnected: true,
        canDisconnect: true,
      );
    case 'Relay':
      return _ConnectionStatus(
        label: 'Relay',
        icon: Icons.alt_route,
        color: const Color(0xFF7DD3FC),
        detail: diagnostics.detail,
        isConnected: true,
        canDisconnect: true,
      );
    case 'Recovering':
      return _ConnectionStatus(
        label: 'Recovering',
        icon: Icons.sync,
        color: const Color(0xFFFBBF24),
        detail: diagnostics.detail,
        isBusy: true,
        canDisconnect: true,
      );
    case 'Connecting':
      return _ConnectionStatus(
        label: 'Connecting',
        icon: Icons.sync,
        color: const Color(0xFFFBBF24),
        detail: diagnostics.detail,
        isBusy: diagnostics.isBusy,
        isConnected: diagnostics.isConnected,
        canDisconnect: diagnostics.canDisconnect,
      );
    case 'Failed':
      return _ConnectionStatus(
        label: 'Failed',
        icon: Icons.error_outline,
        color: const Color(0xFFFF6B6B),
        detail: diagnostics.detail,
      );
    case 'Offline':
      return const _ConnectionStatus(
        label: 'Offline',
        icon: Icons.cloud_off_outlined,
        color: Color(0xFF52646D),
        detail: 'Peer is offline. Keep both apps open.',
      );
    default:
      return _ConnectionStatus(
        label: 'Ready',
        icon: Icons.wifi_tethering,
        color: const Color(0xFF7DD3FC),
        detail: diagnostics.detail,
      );
  }
}

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  static const double _compactBreakpoint = 860;
  static const double _fullscreenFriendsMinWidth = 220;
  static const double _fullscreenFriendsMaxWidth = 380;

  String? _selectedPeerId;
  String? _defaultOutputAppliedCallId;
  String? _lastVoiceCallLifecycleSoundKey;
  double _fullscreenFriendsPanelWidth = 280;
  bool _fullscreenFriendsPanelCollapsed = false;
  bool _fullscreenFriendsPanelForcedOpen = false;

  @override
  Widget build(BuildContext context) {
    final friends = ref.watch(friendsProvider);
    final identity = ref.watch(identityProvider).value;
    final voiceCall = ref.watch(voiceCallProvider);
    final videoRenderers = ref.watch(videoCallRenderersProvider);
    final callSurface = ref.watch(callSurfaceProvider);
    final videoInputCapabilities = ref
        .watch(videoInputCapabilityProvider)
        .value;
    final audioOutputCapabilities = ref
        .watch(audioOutputCapabilityProvider)
        .value;
    final callControlCapabilities =
        (videoInputCapabilities ?? const VideoInputCapabilityState(devices: []))
            .filterCallControls(voiceCall.controlCapabilities);
    final outputRouteOptions = rainVoiceCallOutputRouteOptions(
      hasBluetoothOutput: audioOutputCapabilities?.hasBluetoothOutput ?? false,
    );
    ref.listen<VoiceCallState>(voiceCallProvider, _handleVoiceCallNavigation);

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final isCompact = constraints.maxWidth < _compactBreakpoint;
        final scheme = Theme.of(context).colorScheme;
        final isDark = scheme.brightness == Brightness.dark;

        final showShellHeader = !isCompact || _selectedPeerId == null;

        final shell = SafeArea(
          child: Padding(
            padding: EdgeInsets.all(isCompact ? 8 : 20),
            child: Container(
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF0C1820).withValues(alpha: 0.94)
                    : scheme.surface.withValues(alpha: 0.96),
                borderRadius: BorderRadius.circular(isCompact ? 24 : 32),
                border: Border.all(
                  color: scheme.outlineVariant.withValues(
                    alpha: isDark ? 0.18 : 0.55,
                  ),
                ),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    blurRadius: 36,
                    color: Colors.black.withValues(alpha: isDark ? 0.20 : 0.08),
                    offset: const Offset(0, 20),
                  ),
                ],
              ),
              child: Column(
                children: <Widget>[
                  if (showShellHeader) ...<Widget>[
                    _ShellHeader(identity: identity, isCompact: isCompact),
                    const Divider(height: 1),
                  ],
                  Expanded(
                    child: _buildBodyWithCallSurface(
                      friends: friends,
                      isCompact: isCompact,
                      voiceCall: voiceCall,
                      videoRenderers: videoRenderers,
                      callSurface: callSurface,
                      callControlCapabilities: callControlCapabilities,
                      outputRouteOptions: outputRouteOptions,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
        final content = Stack(
          children: <Widget>[
            Positioned.fill(child: shell),
            if (_shouldShowFullscreenCallWorkspace(callSurface, voiceCall))
              Positioned.fill(
                child: RainFullscreenCallWorkspace(
                  state: voiceCall,
                  displayName: _voiceCallDisplayName(friends, voiceCall),
                  gender: _voiceCallGender(friends, voiceCall),
                  videoRenderers: videoRenderers,
                  primaryRole: callSurface.videoPrimaryRole,
                  onToggleVideoPrimaryRole: () =>
                      _toggleVideoPrimaryRole(voiceCall),
                  onAccept: _acceptVoiceCall,
                  onReject: _rejectVoiceCall,
                  onHangUp: _hangUpVoiceCall,
                  onRetry: () => _retryVoiceCall(voiceCall),
                  onToggleMute: () => _toggleVoiceMute(voiceCall),
                  onToggleDeafen: () => _toggleVoiceDeafen(voiceCall),
                  onToggleCamera: () => _toggleVoiceCamera(voiceCall),
                  onSwitchCamera: _switchVoiceCamera,
                  onSelectOutputRoute: _selectVoiceOutputRoute,
                  controlCapabilities: callControlCapabilities,
                  outputRouteOptions: outputRouteOptions,
                  onExitFullscreen: () =>
                      ref.read(callSurfaceProvider.notifier).exitFullscreen(),
                  friendsPanel: _FriendsListView(
                    friends: friends,
                    selectedPeerId: _selectedPeerId,
                    onSelect: _handleFriendSelection,
                    onRefresh: _refreshFriends,
                  ),
                  showFriendsPanel: !isCompact,
                  friendsPanelCollapsed: _fullscreenFriendsPanelIsCollapsed,
                  friendsPanelWidth: _fullscreenFriendsPanelWidth,
                  onToggleFriendsPanel: _toggleFullscreenFriendsPanel,
                  onResizeFriendsPanel: _resizeFullscreenFriendsPanel,
                ),
              ),
          ],
        );

        return PopScope<Object?>(
          canPop: !_shouldHandleSystemBack(callSurface, isCompact),
          onPopInvokedWithResult: (bool didPop, Object? result) {
            if (didPop) {
              return;
            }
            _handleSystemBack(isCompact);
          },
          child: _wrapFullscreenEscapeHandler(
            callSurface: callSurface,
            child: content,
          ),
        );
      },
    );
  }

  Widget _wrapFullscreenEscapeHandler({
    required CallSurfaceState callSurface,
    required Widget child,
  }) {
    if (!callSurface.isFullscreen) {
      return child;
    }
    return Focus(
      autofocus: true,
      child: CallbackShortcuts(
        bindings: <ShortcutActivator, VoidCallback>{
          const SingleActivator(LogicalKeyboardKey.escape): () {
            ref.read(callSurfaceProvider.notifier).exitFullscreen();
          },
        },
        child: child,
      ),
    );
  }

  bool _shouldHandleSystemBack(CallSurfaceState callSurface, bool isCompact) {
    if (callSurface.isVisible &&
        callSurface.mode != CallSurfaceMode.managerOnly) {
      return true;
    }
    return isCompact && _selectedPeerId != null;
  }

  void _handleSystemBack(bool isCompact) {
    if (ref.read(callSurfaceProvider.notifier).handleBackIntent()) {
      return;
    }
    if (isCompact && _selectedPeerId != null) {
      setState(() => _selectedPeerId = null);
    }
  }

  Widget _buildBodyWithCallSurface({
    required AsyncValue<List<FriendRecord>> friends,
    required bool isCompact,
    required VoiceCallState voiceCall,
    required VideoCallRenderers? videoRenderers,
    required CallSurfaceState callSurface,
    required List<CallControlCapability> callControlCapabilities,
    required List<VoiceCallOutputRouteOption> outputRouteOptions,
  }) {
    final body = isCompact
        ? _buildCompactBody(friends)
        : _buildWideBody(friends);
    return Stack(
      children: <Widget>[
        Positioned.fill(child: body),
        if (callSurface.showsMediaSurface &&
            !(callSurface.mode == CallSurfaceMode.fullscreen &&
                voiceCall.isVideo) &&
            voiceCall.phase != VoiceCallPhase.idle)
          Positioned.fill(
            left: isCompact ? 0 : 321,
            child: RainCallOverlay(
              state: voiceCall,
              surface: callSurface,
              displayName: _voiceCallDisplayName(friends, voiceCall),
              gender: _voiceCallGender(friends, voiceCall),
              videoRenderers: videoRenderers,
              onAccept: _acceptVoiceCall,
              onReject: _rejectVoiceCall,
              onHangUp: _hangUpVoiceCall,
              onRetry: () => _retryVoiceCall(voiceCall),
              onToggleMute: () => _toggleVoiceMute(voiceCall),
              onToggleDeafen: () => _toggleVoiceDeafen(voiceCall),
              onToggleCamera: () => _toggleVoiceCamera(voiceCall),
              onSwitchCamera: _switchVoiceCamera,
              onSelectOutputRoute: _selectVoiceOutputRoute,
              controlCapabilities: callControlCapabilities,
              outputRouteOptions: outputRouteOptions,
              onMinimize: () =>
                  ref.read(callSurfaceProvider.notifier).minimize(),
              onExpand: () => _toggleCallSurfacePanel(callSurface),
              onToggleVideoPrimaryRole: () =>
                  _toggleVideoPrimaryRole(voiceCall),
              onFullscreen: () =>
                  ref.read(callSurfaceProvider.notifier).enterFullscreen(),
              onExitFullscreen: () =>
                  ref.read(callSurfaceProvider.notifier).exitFullscreen(),
              onMoveFloating:
                  (
                    Offset delta,
                    Size viewportSize,
                    EdgeInsets safePadding,
                    Size panelSize,
                  ) => ref
                      .read(callSurfaceProvider.notifier)
                      .moveFloatingPanel(
                        delta: delta,
                        viewportSize: viewportSize,
                        safePadding: safePadding,
                        panelSize: panelSize,
                      ),
              onClampFloating:
                  (Size viewportSize, EdgeInsets safePadding, Size panelSize) =>
                      ref
                          .read(callSurfaceProvider.notifier)
                          .clampFloatingPanel(
                            viewportSize: viewportSize,
                            safePadding: safePadding,
                            panelSize: panelSize,
                          ),
            ),
          ),
        if (callSurface.showsManagerBar &&
            voiceCall.phase != VoiceCallPhase.idle)
          Positioned(
            left: isCompact ? 0 : 321,
            right: 0,
            top: 0,
            child: RainCallManagerBar(
              state: voiceCall,
              surface: callSurface,
              displayName: _voiceCallDisplayName(friends, voiceCall),
              gender: _voiceCallGender(friends, voiceCall),
              onToggleMute: () => _toggleVoiceMute(voiceCall),
              onToggleCamera: () => _toggleVoiceCamera(voiceCall),
              onToggleDeafen: () => _toggleVoiceDeafen(voiceCall),
              onRestore: () => _toggleCallSurfacePanel(callSurface),
              onFullscreen: () =>
                  ref.read(callSurfaceProvider.notifier).enterFullscreen(),
              onHangUp: voiceCall.phase == VoiceCallPhase.incomingRinging
                  ? _rejectVoiceCall
                  : _hangUpVoiceCall,
            ),
          ),
      ],
    );
  }

  bool _shouldShowFullscreenCallWorkspace(
    CallSurfaceState surface,
    VoiceCallState voiceCall,
  ) {
    return surface.mode == CallSurfaceMode.fullscreen &&
        voiceCall.phase != VoiceCallPhase.idle &&
        voiceCall.isVideo;
  }

  bool get _fullscreenFriendsPanelIsCollapsed {
    if (_fullscreenFriendsPanelForcedOpen) {
      return false;
    }
    return _fullscreenFriendsPanelCollapsed || _selectedPeerId != null;
  }

  void _toggleFullscreenFriendsPanel() {
    setState(() {
      if (_fullscreenFriendsPanelIsCollapsed) {
        _fullscreenFriendsPanelCollapsed = false;
        _fullscreenFriendsPanelForcedOpen = true;
      } else {
        _fullscreenFriendsPanelCollapsed = true;
        _fullscreenFriendsPanelForcedOpen = false;
      }
    });
  }

  void _resizeFullscreenFriendsPanel(double delta) {
    if (delta == 0) {
      return;
    }
    setState(() {
      _fullscreenFriendsPanelWidth = (_fullscreenFriendsPanelWidth + delta)
          .clamp(_fullscreenFriendsMinWidth, _fullscreenFriendsMaxWidth)
          .toDouble();
    });
  }

  void _toggleCallSurfacePanel(CallSurfaceState surface) {
    final controller = ref.read(callSurfaceProvider.notifier);
    if (surface.mode == CallSurfaceMode.expanded ||
        surface.mode == CallSurfaceMode.fullscreen) {
      controller.showManagerOnly();
      return;
    }
    controller.restore();
  }

  void _toggleVideoPrimaryRole(VoiceCallState voiceCall) {
    final callId = voiceCall.callId;
    if (callId == null || callId.isEmpty) {
      return;
    }
    ref.read(callSurfaceProvider.notifier).toggleVideoPrimaryRole(callId);
  }

  Widget _buildCompactBody(AsyncValue<List<FriendRecord>> friends) {
    if (_selectedPeerId != null) {
      return _ChatPanel(
        peerId: _selectedPeerId!,
        isCompact: true,
        onBack: () => setState(() => _selectedPeerId = null),
      );
    }

    return _FriendsListView(
      friends: friends,
      selectedPeerId: _selectedPeerId,
      onSelect: _handleFriendSelection,
      onRefresh: _refreshFriends,
      compact: true,
    );
  }

  Widget _buildWideBody(AsyncValue<List<FriendRecord>> friends) {
    return Row(
      children: <Widget>[
        SizedBox(
          width: 320,
          child: _FriendsListView(
            friends: friends,
            selectedPeerId: _selectedPeerId,
            onSelect: _handleFriendSelection,
            onRefresh: _refreshFriends,
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(
          child: _selectedPeerId == null
              ? AppStateMessage(
                  icon: Icons.water_drop_outlined,
                  title: 'Choose a friend',
                  message: 'Open a conversation to start chatting.',
                )
              : _ChatPanel(peerId: _selectedPeerId!),
        ),
      ],
    );
  }

  Future<void> _handleFriendSelection(FriendRecord friend) async {
    setState(() {
      _selectedPeerId = friend.username;
      _fullscreenFriendsPanelForcedOpen = false;
    });
    await ref.read(messagesProvider(friend.username).notifier).markRead();
  }

  void _handleVoiceCallNavigation(
    VoiceCallState? previous,
    VoiceCallState next,
  ) {
    if (!mounted) {
      return;
    }

    _handleVoiceCallSound(previous, next);
    _maybeApplyDefaultVoiceOutput(next);

    if (next.phase != VoiceCallPhase.incomingRinging ||
        next.peerId == null ||
        _selectedPeerId == next.peerId) {
      return;
    }
    setState(() => _selectedPeerId = next.peerId);
  }

  void _maybeApplyDefaultVoiceOutput(VoiceCallState call) {
    final callId = call.callId;
    if (call.phase != VoiceCallPhase.active || callId == null) {
      if (call.phase == VoiceCallPhase.idle ||
          call.phase == VoiceCallPhase.failed) {
        _defaultOutputAppliedCallId = null;
      }
      return;
    }
    if (_defaultOutputAppliedCallId == callId) {
      return;
    }
    _defaultOutputAppliedCallId = callId;
    unawaited(_applyDefaultVoiceOutput(callId));
  }

  Future<void> _applyDefaultVoiceOutput(String callId) async {
    try {
      final settings = await ref.read(voiceAudioSettingsProvider.future);
      final route = _voiceCallOutputRouteForPreference(
        settings.defaultOutputPreference,
      );
      if (route == VoiceCallOutputRoute.systemDefault) {
        return;
      }
      if (!await _isVoiceOutputRouteAvailable(route)) {
        return;
      }
      if (!mounted) {
        return;
      }
      final current = ref.read(voiceCallProvider);
      if (current.callId != callId || current.phase != VoiceCallPhase.active) {
        return;
      }
      await ref.read(voiceCallProvider.notifier).setOutputRoute(route);
    } catch (error) {
      if (mounted) {
        _showVoiceCallError(_formatUiError(error));
      }
    }
  }

  void _handleVoiceCallSound(VoiceCallState? previous, VoiceCallState next) {
    final soundKey = rainVoiceCallLifecycleSoundKeyFor(previous, next);
    if (soundKey == null || soundKey == _lastVoiceCallLifecycleSoundKey) {
      return;
    }
    final event = rainVoiceCallLifecycleSoundEventFor(previous, next);
    if (event == null) {
      return;
    }
    _lastVoiceCallLifecycleSoundKey = soundKey;
    _dispatchSoundEvent(event);
  }

  Future<void> _refreshFriends() async {
    final status = ref.read(networkStatusProvider).value;
    if (status != null && status.blocksNetworkActions) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(status.actionErrorMessage)));
      }
      return;
    }
    await ref.read(friendsProvider.notifier).refresh();
  }

  String _voiceCallDisplayName(
    AsyncValue<List<FriendRecord>> friends,
    VoiceCallState call,
  ) {
    final friend = _voiceCallFriend(friends, call);
    return friend?.displayName ?? call.peerId ?? 'Peer';
  }

  String? _voiceCallGender(
    AsyncValue<List<FriendRecord>> friends,
    VoiceCallState call,
  ) {
    return _voiceCallFriend(friends, call)?.gender?.name;
  }

  FriendRecord? _voiceCallFriend(
    AsyncValue<List<FriendRecord>> friends,
    VoiceCallState call,
  ) {
    final peerId = call.peerId;
    final items = friends.value;
    if (peerId == null || items == null) {
      return null;
    }
    for (final friend in items) {
      if (friend.username == peerId) {
        return friend;
      }
    }
    return null;
  }

  Future<void> _retryVoiceCall(VoiceCallState call) async {
    final peerId = call.peerId;
    if (peerId == null || peerId.trim().isEmpty) {
      _showVoiceCallError('Peer connection is unavailable right now.');
      return;
    }
    if (!call.isOutgoing) {
      _showVoiceCallError('Only the caller can retry this call.');
      return;
    }
    if (call.isVideo) {
      await _startVideoCall(peerId);
    } else {
      await _startVoiceCall(peerId);
    }
  }

  Future<void> _startVoiceCall(String peerId) async {
    final before = ref.read(voiceCallProvider);
    try {
      await ref.read(voiceCallProvider.notifier).start(peerId);
    } catch (error) {
      _dispatchVoiceCommandFailureSound(error, before: before);
      _showVoiceCallError(_formatUiError(error));
    }
  }

  Future<void> _startVideoCall(String peerId) async {
    final before = ref.read(voiceCallProvider);
    try {
      await ref.read(voiceCallProvider.notifier).startVideo(peerId);
    } catch (error) {
      _dispatchVoiceCommandFailureSound(error, before: before);
      _showVoiceCallError(_formatUiError(error));
    }
  }

  Future<void> _acceptVoiceCall() async {
    final before = ref.read(voiceCallProvider);
    try {
      await _stopVoiceCallLoopsBeforeAccept();
      await ref.read(voiceCallProvider.notifier).accept();
    } catch (error) {
      _dispatchVoiceCommandFailureSound(error, before: before);
      _showVoiceCallError(_formatUiError(error));
    }
  }

  Future<void> _rejectVoiceCall() async {
    final before = ref.read(voiceCallProvider);
    try {
      await ref.read(voiceCallProvider.notifier).reject();
    } catch (error) {
      _dispatchVoiceCommandFailureSound(error, before: before);
      _showVoiceCallError(_formatUiError(error));
    }
  }

  Future<void> _hangUpVoiceCall() async {
    final before = ref.read(voiceCallProvider);
    try {
      await ref.read(voiceCallProvider.notifier).hangUp();
    } catch (error) {
      _dispatchVoiceCommandFailureSound(error, before: before);
      _showVoiceCallError(_formatUiError(error));
    }
  }

  Future<void> _toggleVoiceMute(VoiceCallState call) async {
    final nextMuted = !call.isMuted;
    try {
      await ref.read(voiceCallProvider.notifier).setMuted(nextMuted);
      _dispatchSoundEvent(
        nextMuted ? _callControlMuteEvent(call) : _callControlUnmuteEvent(call),
      );
    } catch (error) {
      _dispatchVoiceCommandFailureSound(error, before: call);
      _showVoiceCallError(_formatUiError(error));
    }
  }

  Future<void> _toggleVoiceDeafen(VoiceCallState call) async {
    final nextDeafened = !call.isDeafened;
    try {
      await ref.read(voiceCallProvider.notifier).setDeafened(nextDeafened);
      _dispatchSoundEvent(
        nextDeafened
            ? _callControlDeafenEvent(call)
            : _callControlUndeafenEvent(call),
      );
    } catch (error) {
      _dispatchVoiceCommandFailureSound(error, before: call);
      _showVoiceCallError(_formatUiError(error));
    }
  }

  Future<void> _toggleVoiceCamera(VoiceCallState call) async {
    final nextMuted = !call.isCameraMuted;
    try {
      await ref.read(voiceCallProvider.notifier).setCameraMuted(nextMuted);
      _dispatchSoundEvent(
        nextMuted
            ? _callControlCameraMuteEvent(call)
            : _callControlCameraUnmuteEvent(call),
      );
    } catch (error) {
      _dispatchVoiceCommandFailureSound(error, before: call);
      _showVoiceCallError(_formatUiError(error));
    }
  }

  Future<void> _switchVoiceCamera() async {
    final before = ref.read(voiceCallProvider);
    try {
      await ref.read(voiceCallProvider.notifier).switchCamera();
      _dispatchSoundEvent(_callControlRouteChangedEvent(before));
    } catch (error) {
      _dispatchVoiceCommandFailureSound(error, before: before);
      _showVoiceCallError(_formatUiError(error));
    }
  }

  Future<void> _selectVoiceOutputRoute(VoiceCallOutputRoute route) async {
    final before = ref.read(voiceCallProvider);
    try {
      if (!await _isVoiceOutputRouteAvailable(route)) {
        _showVoiceCallError('Bluetooth audio output is unavailable.');
        return;
      }
      await ref.read(voiceCallProvider.notifier).setOutputRoute(route);
      _dispatchSoundEvent(_callControlRouteChangedEvent(before));
    } catch (error) {
      _dispatchVoiceCommandFailureSound(error, before: before);
      _showVoiceCallError(_formatUiError(error));
    }
  }

  Future<bool> _isVoiceOutputRouteAvailable(VoiceCallOutputRoute route) async {
    if (route != VoiceCallOutputRoute.bluetooth) {
      return true;
    }
    final cached = ref.read(audioOutputCapabilityProvider).value;
    if (cached != null) {
      return cached.hasBluetoothOutput;
    }
    try {
      final capabilities = await ref
          .read(audioOutputCapabilityProvider.notifier)
          .reload();
      return capabilities.hasBluetoothOutput;
    } catch (_) {
      return false;
    }
  }

  Future<void> _stopVoiceCallLoopsBeforeAccept() async {
    try {
      await ref.read(soundEventRouterProvider).stopAllLoops();
    } catch (error) {
      debugPrint('Rain call ringtone cleanup ignored before accept: $error');
    }
  }

  void _dispatchSoundEvent(RainSoundEvent event) {
    _dispatchRainSoundEvent(ref, event);
  }

  void _dispatchVoiceCommandFailureSound(
    Object error, {
    VoiceCallState? before,
  }) {
    _dispatchVoiceCommandFailureSoundForRef(ref, error, before: before);
  }

  void _showVoiceCallError(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Theme.of(context).colorScheme.error,
      ),
    );
  }
}
