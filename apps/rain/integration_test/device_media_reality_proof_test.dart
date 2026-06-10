import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:peer_core/peer_core.dart';

const bool _proofEnabled = bool.fromEnvironment('RAIN_DEVICE_MEDIA_PROOF');
const bool _requireVideo = bool.fromEnvironment(
  'RAIN_DEVICE_MEDIA_REQUIRE_VIDEO',
  defaultValue: true,
);
const MethodChannel _mediaPermissionChannel = MethodChannel(
  'rain/media_permissions',
);
const String _mediaPermissionMethodRequest = 'request';
const String _mediaPermissionRequireVideoKey = 'requireVideo';
const String _mediaPermissionGrantedKey = 'granted';
const String _mediaPermissionMicrophoneGrantedKey = 'microphoneGranted';
const String _mediaPermissionCameraGrantedKey = 'cameraGranted';

// Run with:
// flutter test integration_test\device_media_reality_proof_test.dart `
//   -d emulator-5554 --dart-define=RAIN_DEVICE_MEDIA_PROOF=true
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('real device media capture uses Rain call media stack', (
    WidgetTester _,
  ) async {
    await _requestAndroidMediaPermissions(requireVideo: _requireVideo);

    final platform = FlutterWebRTCBridge();
    final devices = await platform.enumerateMediaDevices();
    final audioInputs = devices
        .where((device) => device.isAudioInputDevice)
        .toList(growable: false);
    final videoInputs = devices
        .where((device) => device.isVideoInputDevice)
        .toList(growable: false);

    debugPrint(
      'RAIN_DEVICE_MEDIA_PROOF audioInputs=${audioInputs.length} '
      'videoInputs=${videoInputs.length} requireVideo=$_requireVideo',
    );

    expect(
      audioInputs,
      isNotEmpty,
      reason:
          'Phase 10 voice proof requires a real or emulated microphone input.',
    );
    if (_requireVideo) {
      expect(
        videoInputs,
        isNotEmpty,
        reason:
            'Phase 10 video proof requires a real or emulated camera input.',
      );
    }

    final connection = DefaultCallMediaConnection(
      config: PeerConfig(
        iceServers: const <Map<String, dynamic>>[],
        platform: platform,
      ),
    );

    try {
      await connection.startLocalMedia(
        kind: _requireVideo ? CallMediaKind.video : CallMediaKind.audio,
      );

      final diagnostics = connection.diagnostics;
      expect(diagnostics.hasLocalAudio, isTrue);
      expect(connection.localStream?.getAudioTracks(), isNotEmpty);
      if (_requireVideo) {
        expect(diagnostics.hasLocalVideo, isTrue);
        expect(connection.localStream?.getVideoTracks(), isNotEmpty);
      }
    } finally {
      await connection.dispose();
    }
  }, skip: !_proofEnabled);
}

Future<void> _requestAndroidMediaPermissions({
  required bool requireVideo,
}) async {
  if (defaultTargetPlatform != TargetPlatform.android) {
    return;
  }

  final result = await _requestNativeMediaPermissions(
    requireVideo: requireVideo,
  );
  if (result.granted) {
    return;
  }

  final missing = <String>[
    if (!result.microphoneGranted) 'microphone',
    if (requireVideo && !result.cameraGranted) 'camera',
  ].join(', ');
  throw StateError(
    'Android media permission request did not grant required permission(s): '
    '$missing.',
  );
}

Future<_AndroidMediaPermissionResult> _requestNativeMediaPermissions({
  required bool requireVideo,
}) async {
  final rawResult = await _mediaPermissionChannel
      .invokeMapMethod<String, Object?>(
        _mediaPermissionMethodRequest,
        <String, Object?>{_mediaPermissionRequireVideoKey: requireVideo},
      );
  return _AndroidMediaPermissionResult.fromMap(rawResult);
}

final class _AndroidMediaPermissionResult {
  const _AndroidMediaPermissionResult({
    required this.granted,
    required this.microphoneGranted,
    required this.cameraGranted,
  });

  factory _AndroidMediaPermissionResult.fromMap(Map<String, Object?>? value) {
    return _AndroidMediaPermissionResult(
      granted: value?[_mediaPermissionGrantedKey] == true,
      microphoneGranted: value?[_mediaPermissionMicrophoneGrantedKey] == true,
      cameraGranted: value?[_mediaPermissionCameraGrantedKey] == true,
    );
  }

  final bool granted;
  final bool microphoneGranted;
  final bool cameraGranted;
}
