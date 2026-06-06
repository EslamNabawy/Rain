import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:peer_core/peer_core.dart';

const bool _proofEnabled = bool.fromEnvironment('RAIN_DEVICE_MEDIA_PROOF');
const bool _requireVideo = bool.fromEnvironment(
  'RAIN_DEVICE_MEDIA_REQUIRE_VIDEO',
  defaultValue: true,
);

// Run with:
// flutter test integration_test\device_media_reality_proof_test.dart `
//   -d emulator-5554 --dart-define=RAIN_DEVICE_MEDIA_PROOF=true
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('real device media capture uses Rain call media stack', (
    WidgetTester _,
  ) async {
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
