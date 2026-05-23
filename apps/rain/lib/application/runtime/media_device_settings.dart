import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:protocol_brain/protocol_brain.dart';

import 'package:rain/infrastructure/services/app_settings_store.dart';

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

  Future<void> selectMicrophone(String? deviceId) async {
    await settingsStore.setSelectedMicrophoneDeviceId(deviceId);
  }

  Future<void> testSelectedMicrophoneAvailability() async {
    final selection = await loadMicrophoneSelection();
    if (selection.hasMissingSelection) {
      throw StateError('Selected microphone is unavailable.');
    }
    MediaStream? stream;
    try {
      stream = await platformBridge.getUserMedia(
        _microphoneTestConstraints(selection.selectedDeviceId),
      );
      if (stream.getAudioTracks().isEmpty) {
        throw StateError('No microphone audio track was captured.');
      }
    } finally {
      if (stream != null) {
        await _disposeMediaStream(stream);
      }
    }
  }

  Map<String, dynamic> _microphoneTestConstraints(String? deviceId) {
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
