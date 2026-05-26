import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:protocol_brain/protocol_brain.dart';

import 'package:rain/infrastructure/services/app_settings_store.dart';
import 'voice_call_state.dart';

const String audioInputDeviceKind = 'audioinput';
const String audioOutputDeviceKind = 'audiooutput';
const String videoInputDeviceKind = 'videoinput';

enum RainMediaDeviceKind {
  audioInput(audioInputDeviceKind, 'Microphone'),
  audioOutput(audioOutputDeviceKind, 'Speaker'),
  videoInput(videoInputDeviceKind, 'Camera'),
  unknown('', 'Device');

  const RainMediaDeviceKind(this.platformKind, this.fallbackLabel);

  final String platformKind;
  final String fallbackLabel;

  static RainMediaDeviceKind fromPlatformKind(String? kind) {
    final normalized = kind?.trim().toLowerCase();
    for (final value in RainMediaDeviceKind.values) {
      if (value.platformKind == normalized && value != unknown) {
        return value;
      }
    }
    return unknown;
  }
}

enum RainCameraFacing { front, rear, external, unknown }

enum AdaptiveDevicePlatform {
  android,
  windows,
  macos,
  linux,
  ios,
  fuchsia,
  unknown,
}

enum AdaptiveInteractionMode { touch, pointer }

enum AdaptiveViewportClass { compact, medium, desktop }

enum AdaptiveRefreshMode { pull, button }

final class AdaptiveDeviceProfile {
  const AdaptiveDeviceProfile({
    required this.platform,
    required this.interactionMode,
    required this.viewportClass,
    required this.refreshMode,
    required this.lowPower,
  });

  factory AdaptiveDeviceProfile.resolve({
    required TargetPlatform targetPlatform,
    required double width,
    required bool lowPower,
  }) {
    final platform = _adaptivePlatformFor(targetPlatform);
    final desktop = _desktopPlatforms.contains(platform);
    final viewportClass = width >= 1100
        ? AdaptiveViewportClass.desktop
        : width >= 720
        ? AdaptiveViewportClass.medium
        : AdaptiveViewportClass.compact;
    return AdaptiveDeviceProfile(
      platform: platform,
      interactionMode: desktop
          ? AdaptiveInteractionMode.pointer
          : AdaptiveInteractionMode.touch,
      viewportClass: viewportClass,
      refreshMode: desktop
          ? AdaptiveRefreshMode.button
          : AdaptiveRefreshMode.pull,
      lowPower: lowPower,
    );
  }

  final AdaptiveDevicePlatform platform;
  final AdaptiveInteractionMode interactionMode;
  final AdaptiveViewportClass viewportClass;
  final AdaptiveRefreshMode refreshMode;
  final bool lowPower;

  bool get isDesktop => _desktopPlatforms.contains(platform);

  bool get isAndroid => platform == AdaptiveDevicePlatform.android;

  bool get usesPointer => interactionMode == AdaptiveInteractionMode.pointer;

  bool get usesPullRefresh => refreshMode == AdaptiveRefreshMode.pull;

  bool get usesRefreshButton => refreshMode == AdaptiveRefreshMode.button;
}

const Set<AdaptiveDevicePlatform> _desktopPlatforms = <AdaptiveDevicePlatform>{
  AdaptiveDevicePlatform.windows,
  AdaptiveDevicePlatform.macos,
  AdaptiveDevicePlatform.linux,
};

AdaptiveDevicePlatform _adaptivePlatformFor(TargetPlatform platform) {
  return switch (platform) {
    TargetPlatform.android => AdaptiveDevicePlatform.android,
    TargetPlatform.windows => AdaptiveDevicePlatform.windows,
    TargetPlatform.macOS => AdaptiveDevicePlatform.macos,
    TargetPlatform.linux => AdaptiveDevicePlatform.linux,
    TargetPlatform.iOS => AdaptiveDevicePlatform.ios,
    TargetPlatform.fuchsia => AdaptiveDevicePlatform.fuchsia,
  };
}

final class RainMediaDevice {
  const RainMediaDevice({
    required this.deviceId,
    required this.label,
    required this.kind,
    this.groupId,
  });

  final String deviceId;
  final String label;
  final String kind;
  final String? groupId;

  RainMediaDeviceKind get typedKind =>
      RainMediaDeviceKind.fromPlatformKind(kind);

  bool get isAudioInput => typedKind == RainMediaDeviceKind.audioInput;

  bool get isAudioOutput => typedKind == RainMediaDeviceKind.audioOutput;

  bool get isVideoInput => typedKind == RainMediaDeviceKind.videoInput;

  bool get hasPermissionLabel => label.trim().isNotEmpty;

  bool get isBluetoothAudioOutput {
    if (!isAudioOutput || !hasPermissionLabel) {
      return false;
    }
    final tokens = _labelTokens(label);
    return _hasAnyToken(tokens, _bluetoothAudioTokens);
  }

  bool get isWiredAudioOutput {
    if (!isAudioOutput || !hasPermissionLabel) {
      return false;
    }
    final tokens = _labelTokens(label);
    return _hasAnyToken(tokens, _wiredAudioTokens);
  }

  bool get isBluetoothAudioInput {
    if (!isAudioInput || !hasPermissionLabel) {
      return false;
    }
    final tokens = _labelTokens(label);
    return _hasAnyToken(tokens, _bluetoothAudioTokens);
  }

  bool get isWiredAudioInput {
    if (!isAudioInput || !hasPermissionLabel) {
      return false;
    }
    final tokens = _labelTokens(label);
    return _hasAnyToken(tokens, _wiredAudioTokens);
  }

  bool get isHeadsetAudioInput {
    if (!isAudioInput || !hasPermissionLabel) {
      return false;
    }
    final tokens = _labelTokens(label);
    return _hasAnyToken(tokens, _headsetAudioTokens);
  }

  RainCameraFacing get cameraFacing {
    if (!isVideoInput || !hasPermissionLabel) {
      return RainCameraFacing.unknown;
    }
    final tokens = _labelTokens(label);
    if (_hasAnyToken(tokens, const <String>{
      'rear',
      'back',
      'environment',
      'world',
      'outward',
    })) {
      return RainCameraFacing.rear;
    }
    if (_hasAnyToken(tokens, const <String>{
      'front',
      'user',
      'selfie',
      'face',
    })) {
      return RainCameraFacing.front;
    }
    if (_hasAnyToken(tokens, const <String>{
      'usb',
      'external',
      'virtual',
      'integrated',
      'built',
      'builtin',
      'webcam',
    })) {
      return RainCameraFacing.external;
    }
    return RainCameraFacing.unknown;
  }

  bool get isLikelyRearFacingCamera =>
      isVideoInput && cameraFacing == RainCameraFacing.rear;

  String displayLabel(int index) {
    final normalized = label.trim();
    if (isAudioInput) {
      return _audioInputDisplayLabel(normalized, index);
    }
    if (normalized.isNotEmpty) {
      return normalized;
    }
    return '${typedKind.fallbackLabel} ${index + 1}';
  }

  String? displayDetailLabel(int index) {
    final normalized = label.trim();
    if (normalized.isEmpty) {
      return null;
    }
    final display = displayLabel(index);
    return display == normalized ? null : normalized;
  }

  String _audioInputDisplayLabel(String normalized, int index) {
    if (normalized.isEmpty) {
      return '${typedKind.fallbackLabel} ${index + 1}';
    }
    final tokens = _labelTokens(normalized);
    if (_hasAnyToken(tokens, _defaultAudioInputTokens)) {
      return 'Default microphone';
    }
    if (_hasAnyToken(tokens, _bluetoothAudioTokens)) {
      return 'Bluetooth mic';
    }
    if (_hasAnyToken(tokens, _wiredHeadsetAudioTokens)) {
      return 'Wired headset mic';
    }
    if (_hasAnyToken(tokens, _usbAudioTokens)) {
      return 'USB microphone';
    }
    if (_hasAnyToken(tokens, _builtInAudioInputTokens)) {
      return 'Built-in microphone';
    }
    return normalized;
  }
}

final class MicrophoneSelectionState {
  const MicrophoneSelectionState({
    required this.devices,
    this.selectedDeviceId,
    this.missingSelectedDeviceId,
  });

  final List<RainMediaDevice> devices;
  final String? selectedDeviceId;
  final String? missingSelectedDeviceId;

  bool get hasMissingSelection => missingSelectedDeviceId != null;

  RainMediaDevice? get selectedDevice {
    final selected = selectedDeviceId;
    if (selected == null) {
      return null;
    }
    for (final device in devices) {
      if (device.deviceId == selected) {
        return device;
      }
    }
    return null;
  }
}

final class VideoInputCapabilityState {
  const VideoInputCapabilityState({
    required this.devices,
    this.selectedDeviceId,
    this.missingSelectedDeviceId,
  });

  final List<RainMediaDevice> devices;
  final String? selectedDeviceId;
  final String? missingSelectedDeviceId;

  int get availableVideoInputCount => devices.length;

  bool get hasMissingSelection => missingSelectedDeviceId != null;

  bool get labelsAvailable =>
      devices.any((RainMediaDevice device) => device.hasPermissionLabel);

  bool get likelyHasRearFacingCamera =>
      labelsAvailable &&
      devices.any((RainMediaDevice device) => device.isLikelyRearFacingCamera);

  bool get supportsCameraSwitch => availableVideoInputCount > 1;

  RainMediaDevice? get selectedDevice {
    final selected = selectedDeviceId;
    if (selected == null) {
      return null;
    }
    for (final device in devices) {
      if (device.deviceId == selected) {
        return device;
      }
    }
    return null;
  }

  List<CallControlCapability> filterCallControls(
    Iterable<CallControlCapability> controls,
  ) {
    if (supportsCameraSwitch) {
      return controls.toList(growable: false);
    }
    return controls
        .where(
          (CallControlCapability capability) =>
              capability != CallControlCapability.switchCamera,
        )
        .toList(growable: false);
  }
}

final class AudioOutputCapabilityState {
  const AudioOutputCapabilityState({
    required this.devices,
    this.selectedRoute = VoiceCallOutputRoute.systemDefault,
  });

  final List<RainMediaDevice> devices;
  final VoiceCallOutputRoute selectedRoute;

  bool get hasBluetoothOutput =>
      devices.any((RainMediaDevice device) => device.isBluetoothAudioOutput);

  bool get hasWiredOutput =>
      devices.any((RainMediaDevice device) => device.isWiredAudioOutput);

  int get availableOutputCount => devices.length;
}

final class AdaptiveAudioOutputTarget {
  const AdaptiveAudioOutputTarget({
    required this.target,
    required this.label,
    this.device,
  });

  final CallAudioOutputTarget target;
  final String label;
  final RainMediaDevice? device;
}

final class AdaptiveMediaCapabilitySnapshot {
  const AdaptiveMediaCapabilitySnapshot({
    required this.profile,
    required this.videoInput,
    required this.audioOutput,
  });

  final AdaptiveDeviceProfile profile;
  final VideoInputCapabilityState videoInput;
  final AudioOutputCapabilityState audioOutput;

  bool get supportsCameraSwitch => videoInput.supportsCameraSwitch;

  bool get hasBluetoothOutput => audioOutput.hasBluetoothOutput;

  bool get hasWiredOutput => audioOutput.hasWiredOutput;

  bool get shouldShowOutputSelector => outputTargets.length > 1;

  bool get supportsAudioOutputSelection => shouldShowOutputSelector;

  List<AdaptiveAudioOutputTarget> get outputTargets {
    if (profile.isAndroid) {
      final defaultLabel = audioOutput.hasWiredOutput
          ? 'Wired headset'
          : 'Phone audio';
      final defaultTarget = audioOutput.hasWiredOutput
          ? const CallAudioOutputTarget.wiredHeadset()
          : const CallAudioOutputTarget.systemDefault();
      return <AdaptiveAudioOutputTarget>[
        AdaptiveAudioOutputTarget(target: defaultTarget, label: defaultLabel),
        const AdaptiveAudioOutputTarget(
          target: CallAudioOutputTarget.androidSpeakerphone(),
          label: 'Speakerphone',
        ),
        if (audioOutput.hasBluetoothOutput)
          const AdaptiveAudioOutputTarget(
            target: CallAudioOutputTarget.bluetooth(),
            label: 'Bluetooth',
          ),
      ];
    }

    if (profile.isDesktop) {
      final outputs = audioOutput.devices
          .where((RainMediaDevice device) => device.isAudioOutput)
          .toList(growable: false);
      if (outputs.length <= 1) {
        return const <AdaptiveAudioOutputTarget>[];
      }
      return <AdaptiveAudioOutputTarget>[
        const AdaptiveAudioOutputTarget(
          target: CallAudioOutputTarget.systemDefault(),
          label: 'System default',
        ),
        for (var index = 0; index < outputs.length; index += 1)
          AdaptiveAudioOutputTarget(
            target: CallAudioOutputTarget.desktopDevice(
              outputs[index].deviceId,
            ),
            label: outputs[index].displayLabel(index),
            device: outputs[index],
          ),
      ];
    }

    return const <AdaptiveAudioOutputTarget>[];
  }

  List<CallControlCapability> filterCallControls(
    Iterable<CallControlCapability> controls,
  ) {
    final videoFiltered = videoInput.filterCallControls(controls);
    if (supportsAudioOutputSelection) {
      return videoFiltered;
    }
    return videoFiltered
        .where(
          (CallControlCapability capability) =>
              capability != CallControlCapability.outputRoute,
        )
        .toList(growable: false);
  }
}

final class StartupMediaPermissionWarmupResult {
  const StartupMediaPermissionWarmupResult({
    required this.microphoneReady,
    required this.cameraReady,
    this.microphoneError,
    this.cameraError,
  });

  final bool microphoneReady;
  final bool cameraReady;
  final Object? microphoneError;
  final Object? cameraError;

  bool get hasFailure => microphoneError != null || cameraError != null;
}

final class StartupMediaPermissionWarmupException implements Exception {
  const StartupMediaPermissionWarmupException({
    this.microphoneError,
    this.cameraError,
  });

  final Object? microphoneError;
  final Object? cameraError;

  @override
  String toString() {
    final parts = <String>[
      if (microphoneError != null) 'microphone: $microphoneError',
      if (cameraError != null) 'camera: $cameraError',
    ];
    return 'Startup media permission warmup failed'
        '${parts.isEmpty ? '' : ' (${parts.join(', ')})'}';
  }
}

class MediaDeviceSettings {
  const MediaDeviceSettings({
    required this.platformBridge,
    required this.settingsStore,
  });

  final PlatformBridge platformBridge;
  final AppSettingsStore settingsStore;

  Future<List<RainMediaDevice>> loadMediaDevices({
    Set<RainMediaDeviceKind> kinds = const <RainMediaDeviceKind>{
      RainMediaDeviceKind.audioInput,
      RainMediaDeviceKind.audioOutput,
      RainMediaDeviceKind.videoInput,
    },
  }) async {
    final devices = await platformBridge.enumerateMediaDevices();
    return devices
        .map(_mapMediaDevice)
        .where((device) {
          return device.deviceId.trim().isNotEmpty &&
              kinds.contains(device.typedKind);
        })
        .toList(growable: false);
  }

  Future<List<RainMediaDevice>> loadAudioInputDevices() async {
    return loadMediaDevices(
      kinds: const <RainMediaDeviceKind>{RainMediaDeviceKind.audioInput},
    );
  }

  Future<List<RainMediaDevice>> loadAudioOutputDevices() async {
    return loadMediaDevices(
      kinds: const <RainMediaDeviceKind>{RainMediaDeviceKind.audioOutput},
    );
  }

  Future<List<RainMediaDevice>> loadVideoInputDevices() async {
    return loadMediaDevices(
      kinds: const <RainMediaDeviceKind>{RainMediaDeviceKind.videoInput},
    );
  }

  Future<MicrophoneSelectionState> loadMicrophoneSelection() async {
    final storedDeviceId = await settingsStore.loadSelectedMicrophoneDeviceId();
    final devices = await loadAudioInputDevices();
    final selectedDeviceId =
        storedDeviceId != null &&
            devices.any((device) => device.deviceId == storedDeviceId)
        ? storedDeviceId
        : null;
    final missingSelectedDeviceId =
        storedDeviceId != null && selectedDeviceId == null
        ? storedDeviceId
        : null;
    return MicrophoneSelectionState(
      devices: devices,
      selectedDeviceId: selectedDeviceId,
      missingSelectedDeviceId: missingSelectedDeviceId,
    );
  }

  Future<VideoInputCapabilityState> loadVideoInputCapabilities() async {
    final storedDeviceId = await settingsStore.loadSelectedVideoInputDeviceId();
    final devices = await loadVideoInputDevices();
    final selectedDeviceId =
        storedDeviceId != null &&
            devices.any((device) => device.deviceId == storedDeviceId)
        ? storedDeviceId
        : null;
    final missingSelectedDeviceId =
        storedDeviceId != null && selectedDeviceId == null
        ? storedDeviceId
        : null;
    return VideoInputCapabilityState(
      devices: devices,
      selectedDeviceId: selectedDeviceId,
      missingSelectedDeviceId: missingSelectedDeviceId,
    );
  }

  Future<AudioOutputCapabilityState> loadAudioOutputCapabilities({
    VoiceCallOutputRoute? selectedRoute,
  }) async {
    final devices = await loadAudioOutputDevices();
    final route =
        selectedRoute ??
        _voiceCallOutputRouteFromPreference(
          await settingsStore.loadDefaultCallAudioOutputPreference(),
        );
    return AudioOutputCapabilityState(devices: devices, selectedRoute: route);
  }

  Future<void> selectMicrophone(String? deviceId) async {
    await settingsStore.setSelectedMicrophoneDeviceId(deviceId);
  }

  Future<void> selectVideoInput(String? deviceId) async {
    await settingsStore.setSelectedVideoInputDeviceId(deviceId);
  }

  Future<void> testSelectedMicrophoneAvailability() async {
    final selection = await loadMicrophoneSelection();
    if (selection.hasMissingSelection) {
      throw StateError('Selected microphone is unavailable.');
    }
    await _probeUserMediaPermission(
      _microphoneConstraints(selection.selectedDeviceId),
      requireAudio: true,
      requireVideo: false,
    );
  }

  Future<StartupMediaPermissionWarmupResult>
  warmUpStartupCallPermissions() async {
    final microphoneAlreadyReady = await settingsStore
        .loadStartupMicrophoneWarmupCompleted();
    final cameraAlreadyReady = await settingsStore
        .loadStartupCameraWarmupCompleted();

    Object? microphoneError;
    Object? cameraError;
    var microphoneReady = microphoneAlreadyReady;
    var cameraReady = cameraAlreadyReady;

    if (!microphoneAlreadyReady) {
      try {
        await _probeUserMediaPermission(
          _microphoneConstraints(null),
          requireAudio: true,
          requireVideo: false,
        );
        microphoneReady = true;
        await settingsStore.setStartupMicrophoneWarmupCompleted(true);
      } catch (error) {
        microphoneError = error;
        await settingsStore.setStartupMicrophoneWarmupCompleted(false);
      }
    }

    if (!cameraAlreadyReady) {
      try {
        await _probeUserMediaPermission(
          _cameraWarmupConstraints(),
          requireAudio: false,
          requireVideo: true,
        );
        cameraReady = true;
        await settingsStore.setStartupCameraWarmupCompleted(true);
      } catch (error) {
        cameraError = error;
        await settingsStore.setStartupCameraWarmupCompleted(false);
      }
    }

    final result = StartupMediaPermissionWarmupResult(
      microphoneReady: microphoneReady,
      cameraReady: cameraReady,
      microphoneError: microphoneError,
      cameraError: cameraError,
    );
    if (result.hasFailure) {
      throw StartupMediaPermissionWarmupException(
        microphoneError: microphoneError,
        cameraError: cameraError,
      );
    }
    return result;
  }

  Map<String, dynamic> _microphoneConstraints(String? deviceId) {
    final audioConstraints = <String, dynamic>{
      'echoCancellation': true,
      'noiseSuppression': true,
      'autoGainControl': true,
    };
    if (deviceId != null) {
      audioConstraints['deviceId'] = deviceId;
    }
    return <String, dynamic>{'audio': audioConstraints, 'video': false};
  }

  Map<String, dynamic> _cameraWarmupConstraints() {
    return const <String, dynamic>{'audio': false, 'video': true};
  }

  Future<void> _probeUserMediaPermission(
    Map<String, dynamic> constraints, {
    required bool requireAudio,
    required bool requireVideo,
  }) async {
    MediaStream? stream;
    try {
      stream = await platformBridge.getUserMedia(constraints);
      if (requireAudio && stream.getAudioTracks().isEmpty) {
        throw StateError('No microphone audio track was captured.');
      }
      if (requireVideo && stream.getVideoTracks().isEmpty) {
        throw StateError('No camera video track was captured.');
      }
    } finally {
      if (stream != null) {
        await _disposeMediaStream(stream);
      }
    }
  }

  Future<void> _disposeMediaStream(MediaStream stream) async {
    for (final track in stream.getTracks()) {
      try {
        await track.stop();
      } catch (_) {
        // Best-effort cleanup after a short microphone probe.
      }
    }
    try {
      await stream.dispose();
    } catch (_) {
      // Best-effort cleanup after a short microphone probe.
    }
  }

  RainMediaDevice _mapMediaDevice(MediaDeviceInfo device) {
    return RainMediaDevice(
      deviceId: device.deviceId.trim(),
      label: device.label.trim(),
      kind: device.kind ?? '',
      groupId: device.groupId,
    );
  }
}

Set<String> _labelTokens(String value) {
  return value
      .toLowerCase()
      .split(RegExp(r'[^a-z0-9]+'))
      .where((String token) => token.isNotEmpty)
      .toSet();
}

bool _hasAnyToken(Set<String> tokens, Set<String> candidates) {
  for (final candidate in candidates) {
    if (tokens.contains(candidate)) {
      return true;
    }
  }
  return false;
}

const Set<String> _bluetoothAudioTokens = <String>{
  'airpods',
  'bluetooth',
  'bt',
  'buds',
  'earbuds',
  'handsfree',
  'wireless',
};

const Set<String> _wiredAudioTokens = <String>{
  'cable',
  'earphones',
  'earpods',
  'headphones',
  'headset',
  'jack',
  'usb',
  'wired',
};

const Set<String> _defaultAudioInputTokens = <String>{'default'};

const Set<String> _wiredHeadsetAudioTokens = <String>{
  'cable',
  'earphones',
  'earpods',
  'headphones',
  'headset',
  'jack',
  'wired',
};

const Set<String> _usbAudioTokens = <String>{'usb', 'usbc'};

const Set<String> _builtInAudioInputTokens = <String>{
  'array',
  'built',
  'builtin',
  'integrated',
  'internal',
};

const Set<String> _headsetAudioTokens = <String>{
  ..._bluetoothAudioTokens,
  ..._wiredAudioTokens,
  'mic',
  'microphone',
};

VoiceCallOutputRoute _voiceCallOutputRouteFromPreference(
  CallAudioOutputPreference preference,
) {
  return switch (preference) {
    CallAudioOutputPreference.systemDefault =>
      VoiceCallOutputRoute.systemDefault,
    CallAudioOutputPreference.speaker => VoiceCallOutputRoute.speaker,
    CallAudioOutputPreference.bluetooth => VoiceCallOutputRoute.bluetooth,
  };
}
