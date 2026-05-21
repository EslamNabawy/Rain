import 'package:peer_core/peer_core.dart';

enum IceProviderTier { stunOnly, primaryRelay, backupRelay, experimentalRelay }

enum IceAttemptStage {
  directStunOnly,
  primaryRelay,
  backupRelay,
  experimentalRelay,
  fullRestart,
}

extension IceAttemptStageX on IceAttemptStage {
  String get wireName => switch (this) {
    IceAttemptStage.directStunOnly => 'directStunOnly',
    IceAttemptStage.primaryRelay => 'primaryRelay',
    IceAttemptStage.backupRelay => 'backupRelay',
    IceAttemptStage.experimentalRelay => 'experimentalRelay',
    IceAttemptStage.fullRestart => 'fullRestart',
  };

  String get label => switch (this) {
    IceAttemptStage.directStunOnly => 'Direct STUN',
    IceAttemptStage.primaryRelay => 'Primary relay',
    IceAttemptStage.backupRelay => 'Backup relay',
    IceAttemptStage.experimentalRelay => 'Experimental relay',
    IceAttemptStage.fullRestart => 'Full restart',
  };

  static IceAttemptStage? fromWireName(String? value) {
    final normalized = value?.trim();
    if (normalized == null || normalized.isEmpty) {
      return null;
    }
    for (final stage in IceAttemptStage.values) {
      if (stage.wireName.toLowerCase() == normalized.toLowerCase()) {
        return stage;
      }
    }
    return null;
  }
}

extension IceProviderTierX on IceProviderTier {
  String get wireName => switch (this) {
    IceProviderTier.stunOnly => 'stunOnly',
    IceProviderTier.primaryRelay => 'primaryRelay',
    IceProviderTier.backupRelay => 'backupRelay',
    IceProviderTier.experimentalRelay => 'experimentalRelay',
  };

  String get label => switch (this) {
    IceProviderTier.stunOnly => 'STUN',
    IceProviderTier.primaryRelay => 'Tier 1',
    IceProviderTier.backupRelay => 'Tier 2',
    IceProviderTier.experimentalRelay => 'Tier 3',
  };

  static IceProviderTier? fromWireName(String? value) {
    final normalized = value?.trim();
    if (normalized == null || normalized.isEmpty) {
      return null;
    }
    for (final tier in IceProviderTier.values) {
      if (tier.wireName.toLowerCase() == normalized.toLowerCase()) {
        return tier;
      }
    }
    return null;
  }
}

class IceAttemptDescriptor {
  const IceAttemptDescriptor({
    required this.stage,
    required this.policy,
    required this.providerTier,
    required this.providerId,
    required this.timeout,
    required this.connectAttemptId,
    required this.attemptIndex,
  });

  final IceAttemptStage stage;
  final PeerIceTransportPolicy policy;
  final IceProviderTier providerTier;
  final String providerId;
  final Duration timeout;
  final String connectAttemptId;
  final int attemptIndex;

  bool get requiresRelay => policy == PeerIceTransportPolicy.relayOnly;
}

class IceAttemptPlan {
  IceAttemptPlan._(this.attempts, this.maxBudget);

  factory IceAttemptPlan.staged({
    required String peerId,
    required String selfUsername,
    required DateTime now,
    bool enableExperimentalRelay = false,
  }) {
    final seed =
        '${now.microsecondsSinceEpoch}-${_normalized(selfUsername)}-${_normalized(peerId)}';
    final attempts = <IceAttemptDescriptor>[
      IceAttemptDescriptor(
        stage: IceAttemptStage.directStunOnly,
        policy: PeerIceTransportPolicy.all,
        providerTier: IceProviderTier.stunOnly,
        providerId: 'stun-pool',
        timeout: const Duration(seconds: 12),
        connectAttemptId: '$seed-0',
        attemptIndex: 0,
      ),
      IceAttemptDescriptor(
        stage: IceAttemptStage.primaryRelay,
        policy: PeerIceTransportPolicy.relayOnly,
        providerTier: IceProviderTier.primaryRelay,
        providerId: 'primary-relay',
        timeout: const Duration(seconds: 30),
        connectAttemptId: '$seed-1',
        attemptIndex: 1,
      ),
      IceAttemptDescriptor(
        stage: IceAttemptStage.backupRelay,
        policy: PeerIceTransportPolicy.relayOnly,
        providerTier: IceProviderTier.backupRelay,
        providerId: 'backup-relay',
        timeout: const Duration(seconds: 20),
        connectAttemptId: '$seed-2',
        attemptIndex: 2,
      ),
      if (enableExperimentalRelay)
        IceAttemptDescriptor(
          stage: IceAttemptStage.experimentalRelay,
          policy: PeerIceTransportPolicy.relayOnly,
          providerTier: IceProviderTier.experimentalRelay,
          providerId: 'experimental-relay',
          timeout: const Duration(seconds: 20),
          connectAttemptId: '$seed-3',
          attemptIndex: 3,
        ),
      IceAttemptDescriptor(
        stage: IceAttemptStage.fullRestart,
        policy: PeerIceTransportPolicy.all,
        providerTier: IceProviderTier.backupRelay,
        providerId: 'full-restart',
        timeout: const Duration(seconds: 25),
        connectAttemptId: '$seed-${enableExperimentalRelay ? 4 : 3}',
        attemptIndex: enableExperimentalRelay ? 4 : 3,
      ),
    ];
    return IceAttemptPlan._(
      List<IceAttemptDescriptor>.unmodifiable(attempts),
      const Duration(seconds: 90),
    );
  }

  final List<IceAttemptDescriptor> attempts;
  final Duration maxBudget;

  IceAttemptDescriptor? get first => attempts.isEmpty ? null : attempts.first;

  IceAttemptDescriptor? after(IceAttemptDescriptor? current) {
    if (current == null) {
      return first;
    }
    final index = attempts.indexWhere(
      (attempt) => attempt.connectAttemptId == current.connectAttemptId,
    );
    if (index < 0 || index + 1 >= attempts.length) {
      return null;
    }
    return attempts[index + 1];
  }

  IceAttemptDescriptor? matchingStage(
    IceAttemptStage stage,
    String connectAttemptId,
  ) {
    for (final attempt in attempts) {
      if (attempt.stage == stage &&
          attempt.connectAttemptId == connectAttemptId) {
        return attempt;
      }
    }
    return null;
  }
}

class IceAttemptResult {
  const IceAttemptResult({
    required this.attempt,
    required this.succeeded,
    required this.completedAt,
    this.failureReason,
    this.route = const PeerConnectionRoute.unknown(),
  });

  final IceAttemptDescriptor attempt;
  final bool succeeded;
  final DateTime completedAt;
  final String? failureReason;
  final PeerConnectionRoute route;
}

class IceProviderMetrics {
  const IceProviderMetrics({
    required this.providerId,
    required this.providerTier,
    this.successCount = 0,
    this.failureCount = 0,
    this.averageSetupMs,
    this.averageRtt,
    this.lastSuccessAt,
    this.lastFailureAt,
    this.lastFailureReason,
  });

  final String providerId;
  final IceProviderTier providerTier;
  final int successCount;
  final int failureCount;
  final double? averageSetupMs;
  final double? averageRtt;
  final DateTime? lastSuccessAt;
  final DateTime? lastFailureAt;
  final String? lastFailureReason;

  bool isCoolingDown(DateTime now, Duration cooldown) {
    final failedAt = lastFailureAt;
    if (failedAt == null) {
      return false;
    }
    final succeededAt = lastSuccessAt;
    if (succeededAt != null && succeededAt.isAfter(failedAt)) {
      return false;
    }
    return now.difference(failedAt) < cooldown;
  }

  IceProviderMetrics record(IceAttemptResult result) {
    if (result.succeeded) {
      return IceProviderMetrics(
        providerId: providerId,
        providerTier: providerTier,
        successCount: successCount + 1,
        failureCount: failureCount,
        averageSetupMs: averageSetupMs,
        averageRtt: _rollingAverage(
          averageRtt,
          result.route.rtt == null ? null : result.route.rtt! * 1000,
          successCount,
        ),
        lastSuccessAt: result.completedAt,
        lastFailureAt: lastFailureAt,
        lastFailureReason: lastFailureReason,
      );
    }
    return IceProviderMetrics(
      providerId: providerId,
      providerTier: providerTier,
      successCount: successCount,
      failureCount: failureCount + 1,
      averageSetupMs: averageSetupMs,
      averageRtt: averageRtt,
      lastSuccessAt: lastSuccessAt,
      lastFailureAt: result.completedAt,
      lastFailureReason: result.failureReason,
    );
  }
}

abstract class IceMetricsStore {
  IceProviderMetrics? read(String providerId);
  void record(IceAttemptResult result);
  bool isCoolingDown(
    String providerId, {
    required DateTime now,
    Duration cooldown = const Duration(minutes: 15),
  });
}

class MemoryIceMetricsStore implements IceMetricsStore {
  final Map<String, IceProviderMetrics> _metrics =
      <String, IceProviderMetrics>{};

  @override
  IceProviderMetrics? read(String providerId) => _metrics[providerId];

  @override
  void record(IceAttemptResult result) {
    final current =
        _metrics[result.attempt.providerId] ??
        IceProviderMetrics(
          providerId: result.attempt.providerId,
          providerTier: result.attempt.providerTier,
        );
    _metrics[result.attempt.providerId] = current.record(result);
  }

  @override
  bool isCoolingDown(
    String providerId, {
    required DateTime now,
    Duration cooldown = const Duration(minutes: 15),
  }) {
    return _metrics[providerId]?.isCoolingDown(now, cooldown) ?? false;
  }
}

String _normalized(String value) => value.trim().toLowerCase();

double? _rollingAverage(double? current, double? next, int sampleCount) {
  if (next == null || next.isNaN || next.isInfinite) {
    return current;
  }
  if (current == null || sampleCount <= 0) {
    return next;
  }
  return ((current * sampleCount) + next) / (sampleCount + 1);
}
