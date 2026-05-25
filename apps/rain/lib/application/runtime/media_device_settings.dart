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
    final normalized = kind?.trim();
    for (final value in RainMediaDeviceKind.values) {
      if (value.platformKind == normalized && value != unknown) {
        return value;
      }
    }
    return unknown;
  }
}

enum RainCameraFacing { front, rear, external, unknown }

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
    if (normalized.isNotEmpty) {
      return normalized;
    }
    return '${typedKind.fallbackLabel} ${index + 1}';
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

  bool get supportsCameraSwitch =>
      availableVideoInputCount > 1 && labelsAvailable;

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
