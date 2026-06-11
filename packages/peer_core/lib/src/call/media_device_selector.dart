/// # media_device_selector.dart
///
/// Selects and validates media input devices (audio/video) against the platform's enumerated device list. Provides diagnostic logging and error recording for device selection failures.
///
/// **Key types:** MediaDeviceSelector
///
/// **Depends on:** flutter_webrtc, platform_bridge

import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../platform_bridge.dart';

typedef DeviceDiagnosticAppender =
    void Function(List<String> states, String value);
typedef DeviceErrorRecorder = void Function(String? error);

class MediaDeviceSelector {
  MediaDeviceSelector({
    required PlatformBridge platform,
    required Future<String?> Function()? audioInputDeviceIdProvider,
    required Future<String?> Function()? videoInputDeviceIdProvider,
    required DeviceDiagnosticAppender appendDiagnostic,
    required DeviceErrorRecorder recordError,
  }) : _platform = platform,
       _audioInputDeviceIdProvider = audioInputDeviceIdProvider,
       _videoInputDeviceIdProvider = videoInputDeviceIdProvider,
       _appendDiagnostic = appendDiagnostic,
       _recordError = recordError;

  final PlatformBridge _platform;
  final Future<String?> Function()? _audioInputDeviceIdProvider;
  final Future<String?> Function()? _videoInputDeviceIdProvider;
  final DeviceDiagnosticAppender _appendDiagnostic;
  final DeviceErrorRecorder _recordError;

  Future<String?> selectedAudioInputDeviceId() async {
    final provider = _audioInputDeviceIdProvider;
    String? selected;
    try {
      selected = (await provider?.call())?.trim();
    } catch (error) {
      _appendDiagnostic(<String>[], 'selectedAudioInputLoad failed | $error');
      _recordError(error.toString());
      return null;
    }
    if (selected == null || selected.isEmpty) {
      return null;
    }

    try {
      final devices = await _platform.enumerateMediaDevices();
      final audioInputs = devices
          .where((MediaDeviceInfo device) => device.isAudioInputDevice)
          .toList(growable: false);
      if (audioInputs.isNotEmpty &&
          !audioInputs.any(
            (MediaDeviceInfo device) => device.deviceId == selected,
          )) {
        _appendDiagnostic(<String>[], 'selectedAudioInputMissing');
        return null;
      }
    } catch (error) {
      _appendDiagnostic(<String>[], 'enumerateMediaDevices failed | $error');
      _recordError(error.toString());
    }

    try {
      await _platform.selectAudioInput(selected);
    } catch (error) {
      _appendDiagnostic(<String>[], 'selectAudioInput failed | $error');
      _recordError(error.toString());
    }
    return selected;
  }

  Future<String?> selectedVideoInputDeviceId() async {
    final provider = _videoInputDeviceIdProvider;
    String? selected;
    try {
      selected = (await provider?.call())?.trim();
    } catch (error) {
      _appendDiagnostic(<String>[], 'selectedVideoInputLoad failed | $error');
      _recordError(error.toString());
      return null;
    }
    if (selected == null || selected.isEmpty) {
      return null;
    }

    try {
      final devices = await _platform.enumerateMediaDevices();
      final videoInputs = devices
          .where((MediaDeviceInfo device) => device.isVideoInputDevice)
          .toList(growable: false);
      if (videoInputs.isNotEmpty &&
          !videoInputs.any(
            (MediaDeviceInfo device) => device.deviceId == selected,
          )) {
        _appendDiagnostic(<String>[], 'selectedVideoInputMissing');
        return null;
      }
    } catch (error) {
      _appendDiagnostic(<String>[], 'enumerateMediaDevices failed | $error');
      _recordError(error.toString());
    }

    return selected;
  }
}
