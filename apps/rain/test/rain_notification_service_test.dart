import 'package:flutter_test/flutter_test.dart';
import 'package:protocol_brain/protocol_brain.dart';
import 'package:rain/infrastructure/notifications/rain_notification_service.dart';

void main() {
  group('RainNotificationService', () {
    test('permission denied returns permissionDenied', () async {
      final platform = _FakeNotificationPlatform(
        permission: RainNotificationPermissionStatus.denied,
      );
      final service = LocalRainNotificationService(platform: platform);

      final result = await service.showConnectionRequest(_surface());

      expect(result.kind, RainNotificationResultKind.permissionDenied);
      expect(result.needsInAppFallback, isTrue);
      expect(platform.shown, isEmpty);
    });

    test('unavailable plugin returns notificationUnavailable', () async {
      final platform = _FakeNotificationPlatform(
        permission: RainNotificationPermissionStatus.unavailable,
      );
      final service = LocalRainNotificationService(platform: platform);

      final result = await service.showConnectionRequest(_surface());

      expect(result.kind, RainNotificationResultKind.notificationUnavailable);
      expect(result.needsInAppFallback, isTrue);
      expect(platform.shown, isEmpty);
    });

    test('blocked and muted requests do not show notifications', () async {
      final platform = _FakeNotificationPlatform();
      final service = LocalRainNotificationService(platform: platform);

      final blocked = await service.showConnectionRequest(
        _surface(
          requestId: 'blocked',
          feedback: const ConnectionRequestFeedbackModel(
            reasonCode: ConnectionRequestReasonCode.blocked,
            message: 'Blocked.',
          ),
        ),
      );
      final muted = await service.showConnectionRequest(
        _surface(
          requestId: 'muted',
          feedback: const ConnectionRequestFeedbackModel(
            reasonCode: ConnectionRequestReasonCode.mutedByReceiver,
            message: 'Muted.',
          ),
        ),
      );

      expect(blocked.kind, RainNotificationResultKind.skipped);
      expect(muted.kind, RainNotificationResultKind.skipped);
      expect(platform.shown, isEmpty);
    });

    test(
      'duplicate inbound request from same peer does not show twice',
      () async {
        final platform = _FakeNotificationPlatform();
        final service = LocalRainNotificationService(platform: platform);

        final first = await service.showConnectionRequest(
          _surface(requestId: 'first'),
        );
        final duplicate = await service.showConnectionRequest(
          _surface(requestId: 'second'),
        );

        expect(first.kind, RainNotificationResultKind.shown);
        expect(duplicate.kind, RainNotificationResultKind.skipped);
        expect(platform.shown, hasLength(1));
      },
    );

    test('notification dismissed on terminal state', () async {
      final platform = _FakeNotificationPlatform();
      final service = LocalRainNotificationService(platform: platform);
      final id = connectionRequestNotificationId('terminal');

      final shown = await service.showConnectionRequest(
        _surface(requestId: 'terminal'),
      );
      final dismissed = await service.dismissConnectionRequest('terminal');
      final terminal = await service.showConnectionRequest(
        _surface(
          requestId: 'terminal-done',
          status: ConnectionRequestStatus.accepted,
        ),
      );

      expect(shown.kind, RainNotificationResultKind.shown);
      expect(dismissed.kind, RainNotificationResultKind.dismissed);
      expect(platform.dismissed, contains(id));
      expect(terminal.kind, RainNotificationResultKind.skipped);
    });
  });
}

class _FakeNotificationPlatform implements RainLocalNotificationPlatform {
  _FakeNotificationPlatform({
    this.permission = RainNotificationPermissionStatus.granted,
  });

  final RainNotificationPermissionStatus permission;
  final List<int> shown = <int>[];
  final List<int> dismissed = <int>[];

  @override
  Future<RainNotificationPermissionStatus>
  prepareConnectionRequestChannel() async => permission;

  @override
  Future<void> show({
    required int id,
    required String title,
    required String body,
    required String payload,
  }) async {
    shown.add(id);
  }

  @override
  Future<void> dismiss(int id) async {
    dismissed.add(id);
  }
}

ConnectionRequestSurfaceModel _surface({
  String requestId = 'request-1',
  String peerId = 'bob',
  ConnectionRequestStatus status = ConnectionRequestStatus.pending,
  ConnectionRequestFeedbackModel? feedback,
}) {
  return ConnectionRequestSurfaceModel(
    requestId: requestId,
    peerId: peerId,
    peerLabel: '@$peerId',
    direction: ConnectionRequestDirection.inbound,
    status: status,
    title: '@$peerId wants to connect',
    subtitle: 'Accept to open the peer lane.',
    feedback: feedback,
    actions: <ConnectionRequestActionModel>[
      ConnectionRequestActionModel(
        kind: ConnectionRequestActionKind.connect,
        label: 'Connect',
        semanticLabel: 'Accept connection request from @$peerId',
        enabled: true,
      ),
      ConnectionRequestActionModel(
        kind: ConnectionRequestActionKind.ignore,
        label: 'Ignore',
        semanticLabel: 'Ignore connection request from @$peerId',
        enabled: true,
      ),
    ],
  );
}
