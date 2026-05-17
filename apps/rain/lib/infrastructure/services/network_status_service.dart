import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_database/firebase_database.dart';

enum NetworkStatusKind { checking, online, offline, limited }

class NetworkStatusState {
  const NetworkStatusState._(this.kind, this.message);

  const NetworkStatusState.checking()
    : this._(NetworkStatusKind.checking, 'Checking internet connection.');
  const NetworkStatusState.online()
    : this._(NetworkStatusKind.online, 'Rain is online.');
  const NetworkStatusState.offline()
    : this._(NetworkStatusKind.offline, 'Offline - cached chats only.');
  const NetworkStatusState.limited()
    : this._(
        NetworkStatusKind.limited,
        'Internet is available, but Rain backend is unreachable.',
      );

  final NetworkStatusKind kind;
  final String message;

  bool get isOnline => kind == NetworkStatusKind.online;

  bool get blocksNetworkActions =>
      kind == NetworkStatusKind.offline || kind == NetworkStatusKind.limited;

  String get actionErrorMessage => switch (kind) {
    NetworkStatusKind.offline =>
      'You are offline. Connect to the internet and try again.',
    NetworkStatusKind.limited =>
      'Rain backend is unreachable. Check your connection and try again.',
    NetworkStatusKind.checking => 'Checking internet connection. Try again.',
    NetworkStatusKind.online => '',
  };

  @override
  bool operator ==(Object other) {
    return other is NetworkStatusState && other.kind == kind;
  }

  @override
  int get hashCode => kind.hashCode;
}

abstract class ConnectivityProbe {
  Future<List<ConnectivityResult>> checkConnectivity();
  Stream<List<ConnectivityResult>> get onConnectivityChanged;
}

class ConnectivityPlusProbe implements ConnectivityProbe {
  ConnectivityPlusProbe({Connectivity? connectivity})
    : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;

  @override
  Future<List<ConnectivityResult>> checkConnectivity() {
    return _connectivity.checkConnectivity();
  }

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged {
    return _connectivity.onConnectivityChanged;
  }
}

abstract class BackendConnectivityProbe {
  Future<bool> checkConnected();
  Stream<bool> watchConnected();
}

class AlwaysConnectedBackendProbe implements BackendConnectivityProbe {
  const AlwaysConnectedBackendProbe();

  @override
  Future<bool> checkConnected() async => true;

  @override
  Stream<bool> watchConnected() => const Stream<bool>.empty();
}

class FirebaseBackendConnectivityProbe implements BackendConnectivityProbe {
  FirebaseBackendConnectivityProbe(this._database);

  final FirebaseDatabase _database;

  DatabaseReference get _connectedRef => _database.ref('.info/connected');

  @override
  Future<bool> checkConnected() async {
    final snapshot = await _connectedRef.get();
    return snapshot.value == true;
  }

  @override
  Stream<bool> watchConnected() {
    return _connectedRef.onValue.map(
      (DatabaseEvent event) => event.snapshot.value == true,
    );
  }
}

class NetworkStatusService {
  NetworkStatusService({
    required ConnectivityProbe connectivityProbe,
    required BackendConnectivityProbe backendProbe,
    Duration backendStartupGrace = const Duration(seconds: 8),
  }) : _connectivityProbe = connectivityProbe,
       _backendProbe = backendProbe,
       _backendStartupGrace = backendStartupGrace;

  final ConnectivityProbe _connectivityProbe;
  final BackendConnectivityProbe _backendProbe;
  final Duration _backendStartupGrace;

  Stream<NetworkStatusState> watch() {
    late StreamController<NetworkStatusState> controller;
    StreamSubscription<List<ConnectivityResult>>? connectivitySubscription;
    StreamSubscription<bool>? backendSubscription;
    Timer? backendStartupGraceTimer;
    List<ConnectivityResult>? latestConnectivity;
    bool latestBackendConnected = true;
    var hasConfirmedBackendOnline = false;
    var backendStartupGraceExpired = false;
    var closed = false;

    void emit(NetworkStatusState status) {
      if (!closed && !controller.isClosed) {
        controller.add(status);
      }
    }

    void cancelBackendStartupGrace() {
      backendStartupGraceTimer?.cancel();
      backendStartupGraceTimer = null;
    }

    NetworkStatusState resolveStatus() {
      final connectivity = latestConnectivity;
      if (connectivity == null) {
        return const NetworkStatusState.checking();
      }
      if (_isOffline(connectivity)) {
        return const NetworkStatusState.offline();
      }
      if (!latestBackendConnected) {
        if (!hasConfirmedBackendOnline && !backendStartupGraceExpired) {
          return const NetworkStatusState.checking();
        }
        return const NetworkStatusState.limited();
      }
      return const NetworkStatusState.online();
    }

    void startBackendStartupGrace() {
      if (hasConfirmedBackendOnline ||
          backendStartupGraceExpired ||
          backendStartupGraceTimer != null) {
        return;
      }
      if (_backendStartupGrace <= Duration.zero) {
        backendStartupGraceExpired = true;
        return;
      }
      backendStartupGraceTimer = Timer(_backendStartupGrace, () {
        backendStartupGraceTimer = null;
        backendStartupGraceExpired = true;
        emit(resolveStatus());
      });
    }

    void updateBackendConnected(bool connected) {
      latestBackendConnected = connected;
      if (connected) {
        hasConfirmedBackendOnline = true;
        backendStartupGraceExpired = false;
        cancelBackendStartupGrace();
      } else if (!_isOffline(
        latestConnectivity ?? const <ConnectivityResult>[],
      )) {
        startBackendStartupGrace();
      }
      emit(resolveStatus());
    }

    Future<void> refreshBackend() async {
      if (_isOffline(latestConnectivity ?? const <ConnectivityResult>[])) {
        latestBackendConnected = false;
        cancelBackendStartupGrace();
        emit(resolveStatus());
        return;
      }
      bool connected;
      try {
        connected = await _backendProbe.checkConnected();
      } catch (_) {
        connected = false;
      }
      updateBackendConnected(connected);
    }

    controller = StreamController<NetworkStatusState>.broadcast(
      onListen: () {
        emit(const NetworkStatusState.checking());
        unawaited(
          _connectivityProbe
              .checkConnectivity()
              .then((List<ConnectivityResult> result) async {
                latestConnectivity = result;
                await refreshBackend();
              })
              .catchError((_) {
                latestConnectivity = const <ConnectivityResult>[
                  ConnectivityResult.none,
                ];
                latestBackendConnected = false;
                emit(resolveStatus());
              }),
        );
        connectivitySubscription = _connectivityProbe.onConnectivityChanged
            .listen((List<ConnectivityResult> result) {
              latestConnectivity = result;
              unawaited(refreshBackend());
            });
        backendSubscription = _backendProbe.watchConnected().listen((
          bool connected,
        ) {
          updateBackendConnected(connected);
        });
      },
      onCancel: () async {
        closed = true;
        cancelBackendStartupGrace();
        await connectivitySubscription?.cancel();
        await backendSubscription?.cancel();
      },
    );

    return controller.stream.distinct();
  }

  static bool _isOffline(List<ConnectivityResult> connectivity) {
    return connectivity.isEmpty ||
        (connectivity.length == 1 &&
            connectivity.first == ConnectivityResult.none);
  }
}
