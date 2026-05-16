import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rain/application/bootstrap/app_bootstrap.dart';
import 'package:rain/core/config/app_environment.dart';
import 'package:rain/main.dart' as rain_app;
import 'package:protocol_brain/protocol_brain.dart';
import 'package:rain/infrastructure/signaling/noop_signaling_adapter.dart';
import 'package:rain/application/runtime/rain_runtime_controller.dart';
import 'package:rain_core/rain_core.dart';

class _FailingBootstrapper extends AppBootstrapper {
  @override
  Future<AppBootstrapState> bootstrap(AppEnvironment environment) async {
    throw StateError('release config missing');
  }
}

class _FailingAuthAdapter extends NoopSignalingAdapter {
  @override
  Future<void> ensureAuthenticated() async {
    throw StateError('auth backend down');
  }
}

class _ExpiredSessionAdapter extends NoopSignalingAdapter {
  @override
  Future<void> ensureAuthenticated() async {
    throw const SignalingSessionExpiredException('sign in again');
  }
}

class _RecordingPresenceAdapter extends NoopSignalingAdapter {
  final List<bool> presenceWrites = <bool>[];

  @override
  Future<void> setPresence(String username, bool online) async {
    presenceWrites.add(online);
    await super.setPresence(username, online);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('app startup failure renders a visible error screen', (
    tester,
  ) async {
    await rain_app.runRainApp(
      environment: AppEnvironment.fromEnvironment(
        runtimeEnvironment: const <String, String>{},
      ),
      bootstrapper: _FailingBootstrapper(),
    );

    await tester.pump();
    await tester.pump();

    expect(find.textContaining('Rain could not start.'), findsOneWidget);
    expect(find.textContaining('release config missing'), findsOneWidget);
  });

  test('runtime startup surfaces signaling authentication failures', () async {
    final db = RainDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final runtime = RainRuntimeController(
      selfIdentity: const RainIdentity(
        username: 'alice',
        displayName: 'Alice',
        createdAt: 0,
        gender: RainGender.female,
      ),
      adapter: _FailingAuthAdapter(),
      brain: null,
      database: db,
      friendStore: FriendStore(db),
      messageStore: MessageStore(db),
      offlineQueueStore: OfflineQueueStore(db),
      messageDeliveryService: MessageDeliveryService(
        messageStore: MessageStore(db),
        offlineQueueStore: OfflineQueueStore(db),
      ),
    );
    addTearDown(runtime.dispose);

    await expectLater(
      runtime.start(),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('Could not authenticate signaling backend'),
        ),
      ),
    );
  });

  test('runtime does not poll friend relationships by default', () {
    final db = RainDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final runtime = RainRuntimeController(
      selfIdentity: const RainIdentity(
        username: 'alice',
        displayName: 'Alice',
        createdAt: 0,
        gender: RainGender.female,
      ),
      adapter: NoopSignalingAdapter(),
      brain: null,
      database: db,
      friendStore: FriendStore(db),
      messageStore: MessageStore(db),
      offlineQueueStore: OfflineQueueStore(db),
      messageDeliveryService: MessageDeliveryService(
        messageStore: MessageStore(db),
        offlineQueueStore: OfflineQueueStore(db),
      ),
    );
    addTearDown(runtime.dispose);

    expect(runtime.friendRequestRefreshInterval, Duration.zero);
  });

  test('runtime startup recovers stuck offline sends to queued', () async {
    final db = RainDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    const identity = RainIdentity(
      username: 'alice',
      displayName: 'Alice',
      createdAt: 0,
      gender: RainGender.female,
    );
    final messageStore = MessageStore(db);
    final offlineQueueStore = OfflineQueueStore(db);
    final envelope = await messageStore.composeOutgoingEnvelope(
      from: 'alice',
      to: 'bob',
      content: 'still needs delivery',
    );
    await messageStore.storeOutgoingEnvelope(
      envelope,
      status: MessageStatus.sent,
    );
    await offlineQueueStore.enqueue(envelope);
    await offlineQueueStore.markStatus(
      envelope.id,
      QueuedMessageStatus.sending,
    );

    final runtime = RainRuntimeController(
      selfIdentity: identity,
      adapter: NoopSignalingAdapter(),
      brain: null,
      database: db,
      friendStore: FriendStore(db),
      messageStore: messageStore,
      offlineQueueStore: offlineQueueStore,
      messageDeliveryService: MessageDeliveryService(
        messageStore: messageStore,
        offlineQueueStore: offlineQueueStore,
      ),
      friendRequestRefreshInterval: Duration.zero,
    );
    addTearDown(runtime.dispose);

    await runtime.start();

    final messageRow =
        await (db.select(db.messages)
              ..where((tbl) => tbl.id.equals(envelope.id))
              ..limit(1))
            .getSingle();
    expect(messageRow.status, MessageStatus.queued.name);
    final queuedRow =
        await (db.select(db.queuedMessages)
              ..where((tbl) => tbl.id.equals(envelope.id))
              ..limit(1))
            .getSingle();
    expect(queuedRow.status, QueuedMessageStatus.queued.name);
  });

  test(
    'runtime startup surfaces expired Firebase session without clearing inside provider',
    () async {
      final db = RainDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await IdentityRepository(db).saveIdentity(
        const RainIdentity(
          username: 'alice',
          displayName: 'Alice',
          createdAt: 0,
          gender: RainGender.female,
        ),
      );

      final runtime = RainRuntimeController(
        selfIdentity: const RainIdentity(
          username: 'alice',
          displayName: 'Alice',
          createdAt: 0,
          gender: RainGender.female,
        ),
        adapter: _ExpiredSessionAdapter(),
        brain: null,
        database: db,
        friendStore: FriendStore(db),
        messageStore: MessageStore(db),
        offlineQueueStore: OfflineQueueStore(db),
        messageDeliveryService: MessageDeliveryService(
          messageStore: MessageStore(db),
          offlineQueueStore: OfflineQueueStore(db),
        ),
      );
      addTearDown(runtime.dispose);

      await expectLater(
        runtime.start(),
        throwsA(isA<SignalingSessionExpiredException>()),
      );

      expect(await IdentityRepository(db).loadIdentity(), isNotNull);
    },
  );

  test('runtime logout clears the local identity session', () async {
    final db = RainDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    const identity = RainIdentity(
      username: 'alice',
      displayName: 'Alice',
      createdAt: 0,
      gender: RainGender.female,
    );
    await IdentityRepository(db).saveIdentity(identity);

    final messageStore = MessageStore(db);
    final offlineQueueStore = OfflineQueueStore(db);
    final runtime = RainRuntimeController(
      selfIdentity: identity,
      adapter: NoopSignalingAdapter(),
      brain: null,
      database: db,
      friendStore: FriendStore(db),
      messageStore: messageStore,
      offlineQueueStore: offlineQueueStore,
      messageDeliveryService: MessageDeliveryService(
        messageStore: messageStore,
        offlineQueueStore: offlineQueueStore,
      ),
      friendRequestRefreshInterval: Duration.zero,
    );
    addTearDown(runtime.dispose);

    await runtime.start();
    await runtime.logOut();

    expect(await IdentityRepository(db).loadIdentity(), isNull);
  });

  test('runtime marks the user offline immediately when app detaches', () async {
    final db = RainDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    const identity = RainIdentity(
      username: 'alice',
      displayName: 'Alice',
      createdAt: 0,
      gender: RainGender.female,
    );
    final adapter = _RecordingPresenceAdapter();
    final runtime = RainRuntimeController(
      selfIdentity: identity,
      adapter: adapter,
      brain: null,
      database: db,
      friendStore: FriendStore(db),
      messageStore: MessageStore(db),
      offlineQueueStore: OfflineQueueStore(db),
      messageDeliveryService: MessageDeliveryService(
        messageStore: MessageStore(db),
        offlineQueueStore: OfflineQueueStore(db),
      ),
      friendRequestRefreshInterval: Duration.zero,
    );
    addTearDown(runtime.dispose);

    await runtime.start();
    runtime.didChangeAppLifecycleState(AppLifecycleState.detached);
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(adapter.presenceWrites.last, isFalse);
  });

  test('desktop shell close policy exits instead of hiding to tray', () {
    final source = File(
      '../../apps/rain/lib/application/bootstrap/app_bootstrap.dart',
    ).readAsStringSync().replaceAll('\r\n', '\n');

    expect(source, contains('windowManager.setPreventClose(false)'));
    expect(source, contains('windowManager.destroy()'));
    expect(source, isNot(contains('windowManager.setPreventClose(true)')));
    expect(source, isNot(contains('windowManager.hide()')));
    expect(source, isNot(contains('trayManager')));
  });
}
