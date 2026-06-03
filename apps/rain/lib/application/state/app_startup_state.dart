import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:protocol_brain/protocol_brain.dart';
import 'package:rain/infrastructure/services/force_update_service.dart';
import 'package:rain/infrastructure/services/network_status_service.dart';
import 'package:rain_core/rain_core.dart';

import 'core_providers.dart';
import 'identity_providers.dart';
import 'runtime_providers.dart';

enum AppStartupPhase {
  checkingUpdate,
  updateRequired,
  validatingSession,
  signedOut,
  startingRuntime,
  sessionExpired,
  failed,
  ready,
}

enum AppStartupFailureSource { forceUpdate, identity, runtime }

@immutable
class AppStartupState {
  const AppStartupState._({
    required this.phase,
    this.updateResult,
    this.identity,
    this.networkStatus,
    this.error,
    this.stackTrace,
    this.failureSource,
  });

  const AppStartupState.checkingUpdate({NetworkStatusState? networkStatus})
    : this._(
        phase: AppStartupPhase.checkingUpdate,
        networkStatus: networkStatus,
      );

  const AppStartupState.updateRequired({
    required ForceUpdateResult updateResult,
    NetworkStatusState? networkStatus,
  }) : this._(
         phase: AppStartupPhase.updateRequired,
         updateResult: updateResult,
         networkStatus: networkStatus,
       );

  const AppStartupState.validatingSession({
    required ForceUpdateResult updateResult,
    NetworkStatusState? networkStatus,
  }) : this._(
         phase: AppStartupPhase.validatingSession,
         updateResult: updateResult,
         networkStatus: networkStatus,
       );

  const AppStartupState.signedOut({
    required ForceUpdateResult updateResult,
    NetworkStatusState? networkStatus,
  }) : this._(
         phase: AppStartupPhase.signedOut,
         updateResult: updateResult,
         networkStatus: networkStatus,
       );

  const AppStartupState.startingRuntime({
    required ForceUpdateResult updateResult,
    required RainIdentity identity,
    NetworkStatusState? networkStatus,
  }) : this._(
         phase: AppStartupPhase.startingRuntime,
         updateResult: updateResult,
         identity: identity,
         networkStatus: networkStatus,
       );

  const AppStartupState.sessionExpired({
    required ForceUpdateResult updateResult,
    required RainIdentity identity,
    required Object error,
    StackTrace? stackTrace,
    NetworkStatusState? networkStatus,
  }) : this._(
         phase: AppStartupPhase.sessionExpired,
         updateResult: updateResult,
         identity: identity,
         networkStatus: networkStatus,
         error: error,
         stackTrace: stackTrace,
         failureSource: AppStartupFailureSource.runtime,
       );

  const AppStartupState.failed({
    required Object error,
    required AppStartupFailureSource failureSource,
    StackTrace? stackTrace,
    ForceUpdateResult? updateResult,
    RainIdentity? identity,
    NetworkStatusState? networkStatus,
  }) : this._(
         phase: AppStartupPhase.failed,
         updateResult: updateResult,
         identity: identity,
         networkStatus: networkStatus,
         error: error,
         stackTrace: stackTrace,
         failureSource: failureSource,
       );

  const AppStartupState.ready({
    required ForceUpdateResult updateResult,
    required RainIdentity identity,
    NetworkStatusState? networkStatus,
  }) : this._(
         phase: AppStartupPhase.ready,
         updateResult: updateResult,
         identity: identity,
         networkStatus: networkStatus,
       );

  final AppStartupPhase phase;
  final ForceUpdateResult? updateResult;
  final RainIdentity? identity;
  final NetworkStatusState? networkStatus;
  final Object? error;
  final StackTrace? stackTrace;
  final AppStartupFailureSource? failureSource;

  bool get showNavigation => phase == AppStartupPhase.ready;

  bool get blocksRoutedSurface => switch (phase) {
    AppStartupPhase.checkingUpdate ||
    AppStartupPhase.updateRequired ||
    AppStartupPhase.validatingSession ||
    AppStartupPhase.startingRuntime ||
    AppStartupPhase.sessionExpired ||
    AppStartupPhase.failed => true,
    AppStartupPhase.signedOut || AppStartupPhase.ready => false,
  };

  bool get isLoading => switch (phase) {
    AppStartupPhase.checkingUpdate ||
    AppStartupPhase.validatingSession ||
    AppStartupPhase.startingRuntime ||
    AppStartupPhase.sessionExpired => true,
    _ => false,
  };

  String? get networkStatusMessage =>
      networkStatus != null && networkStatus!.blocksNetworkActions
      ? networkStatus!.message
      : null;
}

final appStartupStateProvider = Provider<AppStartupState>((Ref ref) {
  final networkStatus = ref.watch(networkStatusProvider).value;
  final forceUpdate = ref.watch(forceUpdateProvider);
  if (!forceUpdate.hasValue) {
    if (forceUpdate.hasError) {
      return AppStartupState.failed(
        error: forceUpdate.error!,
        stackTrace: forceUpdate.stackTrace,
        failureSource: AppStartupFailureSource.forceUpdate,
        networkStatus: networkStatus,
      );
    }
    return AppStartupState.checkingUpdate(networkStatus: networkStatus);
  }

  final updateResult = forceUpdate.requireValue;
  if (updateResult.requiresUpdate) {
    return AppStartupState.updateRequired(
      updateResult: updateResult,
      networkStatus: networkStatus,
    );
  }

  final identity = ref.watch(identityProvider);
  if (!identity.hasValue) {
    if (identity.hasError) {
      return AppStartupState.failed(
        error: identity.error!,
        stackTrace: identity.stackTrace,
        failureSource: AppStartupFailureSource.identity,
        updateResult: updateResult,
        networkStatus: networkStatus,
      );
    }
    return AppStartupState.validatingSession(
      updateResult: updateResult,
      networkStatus: networkStatus,
    );
  }

  final currentIdentity = identity.requireValue;
  if (currentIdentity == null) {
    return AppStartupState.signedOut(
      updateResult: updateResult,
      networkStatus: networkStatus,
    );
  }

  final runtime = ref.watch(runtimeControllerProvider);
  if (!runtime.hasValue) {
    if (runtime.hasError) {
      final error = runtime.error!;
      if (error is SignalingSessionExpiredException) {
        return AppStartupState.sessionExpired(
          updateResult: updateResult,
          identity: currentIdentity,
          error: error,
          stackTrace: runtime.stackTrace,
          networkStatus: networkStatus,
        );
      }
      return AppStartupState.failed(
        error: error,
        stackTrace: runtime.stackTrace,
        failureSource: AppStartupFailureSource.runtime,
        updateResult: updateResult,
        identity: currentIdentity,
        networkStatus: networkStatus,
      );
    }
    return AppStartupState.startingRuntime(
      updateResult: updateResult,
      identity: currentIdentity,
      networkStatus: networkStatus,
    );
  }

  return AppStartupState.ready(
    updateResult: updateResult,
    identity: currentIdentity,
    networkStatus: networkStatus,
  );
});
