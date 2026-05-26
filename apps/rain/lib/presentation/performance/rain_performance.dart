import 'dart:ffi' as ffi;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

enum RainPerformanceTier { standard, lowPower }

class RainPerformanceProfile {
  const RainPerformanceProfile({
    required this.tier,
    required this.reason,
    required this.abiName,
  });

  factory RainPerformanceProfile.detect({String? override, String? abiName}) {
    final requested = (override ?? _performanceTierOverride).trim();
    final normalizedOverride = requested.toLowerCase();
    final resolvedAbiName = abiName ?? _currentAbiName();
    if (_isLowPowerOverride(normalizedOverride)) {
      return RainPerformanceProfile(
        tier: RainPerformanceTier.lowPower,
        reason: 'override:$requested',
        abiName: resolvedAbiName,
      );
    }
    if (_isStandardOverride(normalizedOverride)) {
      return RainPerformanceProfile(
        tier: RainPerformanceTier.standard,
        reason: 'override:$requested',
        abiName: resolvedAbiName,
      );
    }
    if (_isArmV7Abi(resolvedAbiName)) {
      return RainPerformanceProfile(
        tier: RainPerformanceTier.lowPower,
        reason: 'android-armv7',
        abiName: resolvedAbiName,
      );
    }
    return RainPerformanceProfile(
      tier: RainPerformanceTier.standard,
      reason: 'default',
      abiName: resolvedAbiName,
    );
  }

  static const String _performanceTierOverride = String.fromEnvironment(
    'RAIN_PERFORMANCE_TIER',
  );

  final RainPerformanceTier tier;
  final String reason;
  final String abiName;

  bool get isLowPower => tier == RainPerformanceTier.lowPower;

  Map<String, Object> toJson() => <String, Object>{
    'tier': tier.name,
    'reason': reason,
    'abiName': abiName,
  };

  static bool _isLowPowerOverride(String value) {
    return value == 'lowpower' ||
        value == 'low_power' ||
        value == 'low-power' ||
        value == 'armv7' ||
        value == 'v7';
  }

  static bool _isStandardOverride(String value) {
    return value == 'standard' || value == 'normal' || value == 'default';
  }

  static bool _isArmV7Abi(String value) {
    final normalized = value.toLowerCase();
    return normalized == 'androidarm' ||
        normalized == 'abi.androidarm' ||
        normalized.contains('armeabi-v7a') ||
        normalized.contains('android-arm') && !normalized.contains('64');
  }

  static String _currentAbiName() {
    if (kIsWeb) {
      return 'web';
    }
    try {
      return ffi.Abi.current().toString();
    } catch (_) {
      return 'unknown';
    }
  }
}

class RainPerformanceScope extends InheritedWidget {
  const RainPerformanceScope({
    super.key,
    required this.profile,
    required super.child,
  });

  static final RainPerformanceProfile _fallback =
      RainPerformanceProfile.detect();

  final RainPerformanceProfile profile;

  static RainPerformanceProfile of(BuildContext context) {
    return context
            .dependOnInheritedWidgetOfExactType<RainPerformanceScope>()
            ?.profile ??
        _fallback;
  }

  static RainPerformanceProfile read(BuildContext context) {
    final scope =
        context
                .getElementForInheritedWidgetOfExactType<RainPerformanceScope>()
                ?.widget
            as RainPerformanceScope?;
    return scope?.profile ?? _fallback;
  }

  static RainPerformanceProfile? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<RainPerformanceScope>()
        ?.profile;
  }

  @override
  bool updateShouldNotify(RainPerformanceScope oldWidget) {
    return oldWidget.profile.tier != profile.tier ||
        oldWidget.profile.reason != profile.reason ||
        oldWidget.profile.abiName != profile.abiName;
  }
}
