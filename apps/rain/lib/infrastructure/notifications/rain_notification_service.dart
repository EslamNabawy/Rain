import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:protocol_brain/protocol_brain.dart';

import 'package:rain/infrastructure/services/app_settings_store.dart';

typedef RainConnectionRequestSettingsLoader =
    FutureOr<AppConnectionRequestSettings> Function();
typedef RainAppLifecycleStateReader = AppLifecycleState? Function();

enum RainNotificationPermissionStatus { granted, denied, unavailable }

enum RainNotificationResultKind {
  shown,
  dismissed,
  skipped,
  permissionDenied,
  notificationUnavailable,
}

final class RainNotificationResult {
  const RainNotificationResult._({
    required this.kind,
    required this.message,
    this.requestId,
    this.peerId,
  });

  const RainNotificationResult.shown({
    required String requestId,
    required String peerId,
  }) : this._(
         kind: RainNotificationResultKind.shown,
         message: 'Connection request notification shown.',
         requestId: requestId,
         peerId: peerId,
       );

  const RainNotificationResult.dismissed({
    required String requestId,
    String? peerId,
  }) : this._(
         kind: RainNotificationResultKind.dismissed,
         message: 'Connection request notification dismissed.',
         requestId: requestId,
         peerId: peerId,
       );

  const RainNotificationResult.skipped({
    required String message,
    String? requestId,
    String? peerId,
  }) : this._(
         kind: RainNotificationResultKind.skipped,
         message: message,
         requestId: requestId,
         peerId: peerId,
       );

  const RainNotificationResult.permissionDenied({
    String? requestId,
    String? peerId,
  }) : this._(
         kind: RainNotificationResultKind.permissionDenied,
         message:
             'Notifications are disabled. You will still see requests inside Rain.',
         requestId: requestId,
         peerId: peerId,
       );

  const RainNotificationResult.notificationUnavailable({
    String? requestId,
    String? peerId,
  }) : this._(
         kind: RainNotificationResultKind.notificationUnavailable,
         message:
             'Notification delivery is unavailable. You will still see requests inside Rain.',
         requestId: requestId,
         peerId: peerId,
       );

  final RainNotificationResultKind kind;
  final String message;
  final String? requestId;
  final String? peerId;

  bool get needsInAppFallback =>
      kind == RainNotificationResultKind.permissionDenied ||
      kind == RainNotificationResultKind.notificationUnavailable;
}

abstract interface class RainNotificationService {
  Future<RainNotificationResult> showConnectionRequest(
    ConnectionRequestSurfaceModel surface,
  );

  Future<RainNotificationResult> dismissConnectionRequest(String requestId);

  Future<void> dismissConnectionRequestsFromPeer(String peerId);
}

abstract interface class RainLocalNotificationPlatform {
  Future<RainNotificationPermissionStatus> prepareConnectionRequestChannel();

  Future<void> show({
    required int id,
    required String title,
    required String body,
    required String payload,
  });

  Future<void> dismiss(int id);
}

final class NoopRainNotificationService implements RainNotificationService {
  const NoopRainNotificationService();

  @override
  Future<RainNotificationResult> showConnectionRequest(
    ConnectionRequestSurfaceModel surface,
  ) async {
    return RainNotificationResult.notificationUnavailable(
      requestId: surface.requestId,
      peerId: surface.peerId,
    );
  }

  @override
  Future<RainNotificationResult> dismissConnectionRequest(
    String requestId,
  ) async {
    return RainNotificationResult.dismissed(requestId: requestId);
  }

  @override
  Future<void> dismissConnectionRequestsFromPeer(String peerId) async {}
}

final class LocalRainNotificationService implements RainNotificationService {
  LocalRainNotificationService({
    required RainLocalNotificationPlatform platform,
    RainConnectionRequestSettingsLoader? settingsLoader,
    RainAppLifecycleStateReader? lifecycleStateReader,
  }) : _platform = platform,
       _settingsLoader =
           settingsLoader ?? (() => const AppConnectionRequestSettings()),
       _lifecycleStateReader = lifecycleStateReader ?? (() => null);

  final RainLocalNotificationPlatform _platform;
  final RainConnectionRequestSettingsLoader _settingsLoader;
  final RainAppLifecycleStateReader _lifecycleStateReader;
  final Map<String, int> _activeIdsByRequestId = <String, int>{};
  final Map<String, String> _activeRequestIdByPeerId = <String, String>{};

  @override
  Future<RainNotificationResult> showConnectionRequest(
    ConnectionRequestSurfaceModel surface,
  ) async {
    final skipMessage = _skipReason(surface);
    if (skipMessage != null) {
      return RainNotificationResult.skipped(
        message: skipMessage,
        requestId: surface.requestId,
        peerId: surface.peerId,
      );
    }
    if (_activeIdsByRequestId.containsKey(surface.requestId)) {
      return RainNotificationResult.skipped(
        message: 'Connection request notification is already visible.',
        requestId: surface.requestId,
        peerId: surface.peerId,
      );
    }
    final activePeerRequestId = _activeRequestIdByPeerId[surface.peerId];
    if (activePeerRequestId != null &&
        activePeerRequestId != surface.requestId) {
      return RainNotificationResult.skipped(
        message:
            'A connection request from ${surface.peerLabel} is already visible.',
        requestId: surface.requestId,
        peerId: surface.peerId,
      );
    }
    final settings = await Future<AppConnectionRequestSettings>.value(
      _settingsLoader(),
    );
    if (!settings.notificationsEnabled) {
      return _skipAndDismiss(
        surface,
        'Connection request notifications are disabled.',
      );
    }
    if (!_shouldNotifyForLifecycle(settings)) {
      return _skipAndDismiss(
        surface,
        'Connection request notifications are hidden while Rain is minimized.',
      );
    }

    final permission = await _platform.prepareConnectionRequestChannel();
    switch (permission) {
      case RainNotificationPermissionStatus.granted:
        break;
      case RainNotificationPermissionStatus.denied:
        return RainNotificationResult.permissionDenied(
          requestId: surface.requestId,
          peerId: surface.peerId,
        );
      case RainNotificationPermissionStatus.unavailable:
        return RainNotificationResult.notificationUnavailable(
          requestId: surface.requestId,
          peerId: surface.peerId,
        );
    }

    final id = connectionRequestNotificationId(surface.requestId);
    await _platform.show(
      id: id,
      title: surface.title,
      body: surface.subtitle,
      payload: 'connection-request:${surface.requestId}:${surface.peerId}',
    );
    _activeIdsByRequestId[surface.requestId] = id;
    _activeRequestIdByPeerId[surface.peerId] = surface.requestId;
    return RainNotificationResult.shown(
      requestId: surface.requestId,
      peerId: surface.peerId,
    );
  }

  Future<RainNotificationResult> _skipAndDismiss(
    ConnectionRequestSurfaceModel surface,
    String message,
  ) async {
    await dismissConnectionRequest(surface.requestId);
    return RainNotificationResult.skipped(
      message: message,
      requestId: surface.requestId,
      peerId: surface.peerId,
    );
  }

  @override
  Future<RainNotificationResult> dismissConnectionRequest(
    String requestId,
  ) async {
    final id = _activeIdsByRequestId.remove(requestId);
    if (id != null) {
      await _platform.dismiss(id);
    }
    String? dismissedPeerId;
    _activeRequestIdByPeerId.removeWhere((String peerId, String activeId) {
      final matches = activeId == requestId;
      if (matches) {
        dismissedPeerId = peerId;
      }
      return matches;
    });
    return RainNotificationResult.dismissed(
      requestId: requestId,
      peerId: dismissedPeerId,
    );
  }

  @override
  Future<void> dismissConnectionRequestsFromPeer(String peerId) async {
    final requestId = _activeRequestIdByPeerId.remove(peerId);
    if (requestId == null) {
      return;
    }
    await dismissConnectionRequest(requestId);
  }

  String? _skipReason(ConnectionRequestSurfaceModel surface) {
    if (surface.direction != ConnectionRequestDirection.inbound) {
      return 'Only inbound connection requests can notify.';
    }
    if (surface.status.isTerminal) {
      return 'Terminal connection requests do not notify.';
    }
    if (!surface.actions.any(
      (ConnectionRequestActionModel action) =>
          action.kind == ConnectionRequestActionKind.connect && action.enabled,
    )) {
      return 'Connection request has no available connect action.';
    }
    return switch (surface.feedback?.reasonCode) {
      ConnectionRequestReasonCode.blocked =>
        'Blocked connection requests do not notify.',
      ConnectionRequestReasonCode.mutedByReceiver =>
        'Muted connection requests do not notify.',
      ConnectionRequestReasonCode.duplicatePendingRequest =>
        'Duplicate connection requests do not notify.',
      _ => null,
    };
  }

  bool _shouldNotifyForLifecycle(AppConnectionRequestSettings settings) {
    final lifecycleState = _lifecycleStateReader();
    if (lifecycleState == null || lifecycleState == AppLifecycleState.resumed) {
      return true;
    }
    return settings.showNotificationsWhenMinimized;
  }
}

final class FlutterLocalRainNotificationPlatform
    implements RainLocalNotificationPlatform {
  FlutterLocalRainNotificationPlatform({
    FlutterLocalNotificationsPlugin? plugin,
    TargetPlatform? targetPlatform,
  }) : _plugin = plugin ?? FlutterLocalNotificationsPlugin(),
       _targetPlatform = targetPlatform;

  static const String connectionRequestChannelId = 'rain_connection_requests';
  static const String connectionRequestChannelName = 'Connection requests';
  static const String connectionRequestChannelDescription =
      'Notifies when an accepted friend asks to open a peer lane.';

  final FlutterLocalNotificationsPlugin _plugin;
  final TargetPlatform? _targetPlatform;
  Future<bool?>? _initializing;
  bool _channelReady = false;

  TargetPlatform get _platform => _targetPlatform ?? defaultTargetPlatform;

  @override
  Future<RainNotificationPermissionStatus>
  prepareConnectionRequestChannel() async {
    final initialized = await _ensureInitialized();
    if (initialized != true) {
      return RainNotificationPermissionStatus.unavailable;
    }
    if (_platform == TargetPlatform.android) {
      final androidPlugin = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      if (androidPlugin == null) {
        return RainNotificationPermissionStatus.unavailable;
      }
      if (!_channelReady) {
        await androidPlugin.createNotificationChannel(
          const AndroidNotificationChannel(
            connectionRequestChannelId,
            connectionRequestChannelName,
            description: connectionRequestChannelDescription,
            importance: Importance.high,
          ),
        );
        _channelReady = true;
      }
      final enabled = await androidPlugin.areNotificationsEnabled();
      if (enabled == true) {
        return RainNotificationPermissionStatus.granted;
      }
      final granted = await androidPlugin.requestNotificationsPermission();
      return granted == true
          ? RainNotificationPermissionStatus.granted
          : RainNotificationPermissionStatus.denied;
    }
    if (_platform == TargetPlatform.windows) {
      return RainNotificationPermissionStatus.granted;
    }
    return RainNotificationPermissionStatus.unavailable;
  }

  @override
  Future<void> show({
    required int id,
    required String title,
    required String body,
    required String payload,
  }) {
    return _plugin.show(
      id: id,
      title: title,
      body: body,
      payload: payload,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          connectionRequestChannelId,
          connectionRequestChannelName,
          channelDescription: connectionRequestChannelDescription,
          importance: Importance.high,
          priority: Priority.high,
          category: AndroidNotificationCategory.message,
          onlyAlertOnce: true,
        ),
        windows: WindowsNotificationDetails(
          duration: WindowsNotificationDuration.short,
          subtitle: 'Connection request',
        ),
      ),
    );
  }

  @override
  Future<void> dismiss(int id) => _plugin.cancel(id: id);

  Future<bool?> _ensureInitialized() {
    return _initializing ??= _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        windows: WindowsInitializationSettings(
          appName: 'Rain',
          appUserModelId: 'Rain.PeerLink.App',
          guid: '0a2f2ac6-c64f-4b7d-91ad-cc41b1b1f7e3',
        ),
      ),
    );
  }
}

int connectionRequestNotificationId(String requestId) {
  var hash = 0x811c9dc5;
  for (final codeUnit in requestId.codeUnits) {
    hash ^= codeUnit;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return hash & 0x7fffffff;
}
