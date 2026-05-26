import 'dart:convert';

import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

const String rainReleaseManifestRemoteConfigKey = 'rain_release_manifest_v1';

enum AppUpdateChannel {
  stable,
  demo;

  static AppUpdateChannel parse(String value) {
    final normalized = value.trim().toLowerCase();
    for (final channel in AppUpdateChannel.values) {
      if (channel.name == normalized) {
        return channel;
      }
    }
    return AppUpdateChannel.stable;
  }
}

enum VersionCheckStatus {
  current,
  optionalUpdateAvailable,
  updateRequired,
  checkUnavailable,
  invalidConfig,
}

typedef ForceUpdateStatus = VersionCheckStatus;

class AppVersionInfo {
  const AppVersionInfo({
    required this.version,
    required this.buildNumber,
    required this.platform,
    required this.channel,
  });

  factory AppVersionInfo.fromPackageInfo({
    required PackageInfo packageInfo,
    required AppUpdateChannel channel,
    required String platform,
  }) {
    return AppVersionInfo(
      version: packageInfo.version.trim(),
      buildNumber: int.tryParse(packageInfo.buildNumber.trim()) ?? 0,
      platform: platform,
      channel: channel,
    );
  }

  final String version;
  final int buildNumber;
  final String platform;
  final AppUpdateChannel channel;

  String get displayBuild => buildNumber <= 0 ? 'unknown' : '$buildNumber';
}

class ReleaseVersionPolicy {
  const ReleaseVersionPolicy({
    required this.updateUrl,
    this.latestVersion,
    this.latestBuild,
    this.minimumVersion,
    this.minimumBuild,
    this.notes,
    this.publishedAt,
  });

  factory ReleaseVersionPolicy.fromJson(
    Map<String, dynamic> json, {
    required String fallbackUpdateUrl,
  }) {
    return ReleaseVersionPolicy(
      latestVersion: _optionalString(json['latestVersion']),
      latestBuild: _optionalInt(json['latestBuild']),
      minimumVersion: _optionalString(json['minimumVersion']),
      minimumBuild: _optionalInt(json['minimumBuild']),
      updateUrl: _optionalString(json['updateUrl']) ?? fallbackUpdateUrl,
      notes: _optionalString(json['notes']),
      publishedAt: _optionalInt(json['publishedAt']),
    );
  }

  factory ReleaseVersionPolicy.legacy({
    required String minimumVersion,
    required String updateUrl,
  }) {
    return ReleaseVersionPolicy(
      minimumVersion: minimumVersion.trim().isEmpty
          ? null
          : minimumVersion.trim(),
      updateUrl: updateUrl,
    );
  }

  final String? latestVersion;
  final int? latestBuild;
  final String? minimumVersion;
  final int? minimumBuild;
  final String updateUrl;
  final String? notes;
  final int? publishedAt;

  bool get hasAnyVersionPolicy =>
      latestVersion != null ||
      latestBuild != null ||
      minimumVersion != null ||
      minimumBuild != null;
}

class VersionCheckResult {
  const VersionCheckResult({
    required this.status,
    required this.currentVersion,
    required this.minVersion,
    required this.updateUrl,
    this.currentBuild = 0,
    this.latestVersion,
    this.latestBuild,
    this.minimumBuild,
    this.platform = 'unknown',
    this.channel = AppUpdateChannel.stable,
    this.notes,
    this.publishedAt,
    this.failureReason,
  });

  final VersionCheckStatus status;
  final String currentVersion;
  final int currentBuild;
  final String minVersion;
  final int? minimumBuild;
  final String? latestVersion;
  final int? latestBuild;
  final String updateUrl;
  final String platform;
  final AppUpdateChannel channel;
  final String? notes;
  final int? publishedAt;
  final String? failureReason;

  bool get requiresUpdate => status == VersionCheckStatus.updateRequired;

  bool get hasOptionalUpdate =>
      status == VersionCheckStatus.optionalUpdateAvailable;

  String get displayCurrentBuild =>
      currentBuild <= 0 ? 'unknown' : '$currentBuild';

  String get displayLatestVersion => latestVersion ?? currentVersion;

  String get displayLatestBuild =>
      latestBuild == null ? 'unknown' : '${latestBuild!}';

  String get displayMinimumBuild =>
      minimumBuild == null ? 'none' : '${minimumBuild!}';

  String get optionalUpdateDismissalKey {
    final latest = latestVersion ?? currentVersion;
    final build = latestBuild ?? 0;
    return '${channel.name}|$platform|$latest|$build';
  }
}

typedef ForceUpdateResult = VersionCheckResult;

class ForceUpdateConfig {
  const ForceUpdateConfig({required this.minVersion, required this.updateUrl});

  final String minVersion;
  final String updateUrl;
}

typedef ForceUpdateConfigLoader = Future<ForceUpdateConfig?> Function();
typedef ReleaseManifestLoader = Future<String?> Function();

class ForceUpdateService {
  ForceUpdateService({
    required FirebaseRemoteConfig? remoteConfig,
    required this.updateUrl,
    this.updateChannel = AppUpdateChannel.stable,
    String? platform,
    ForceUpdateConfigLoader? configLoader,
    ReleaseManifestLoader? manifestLoader,
    Future<PackageInfo> Function()? packageInfoLoader,
    Future<bool> Function()? fetchAndActivate,
  }) : _remoteConfig = remoteConfig,
       _platform = platform,
       _configLoader = configLoader,
       _manifestLoader = manifestLoader,
       _packageInfoLoader = packageInfoLoader,
       _fetchAndActivate = fetchAndActivate;

  final FirebaseRemoteConfig? _remoteConfig;
  final String updateUrl;
  final AppUpdateChannel updateChannel;
  final String? _platform;
  final ForceUpdateConfigLoader? _configLoader;
  final ReleaseManifestLoader? _manifestLoader;
  final Future<PackageInfo> Function()? _packageInfoLoader;
  final Future<bool> Function()? _fetchAndActivate;
  ReleaseVersionPolicy? _lastKnownPolicy;

  Future<VersionCheckResult> check() async {
    final appVersion = await _loadAppVersionInfo();

    try {
      final policy = await _loadPolicy();
      if (policy == null || !policy.hasAnyVersionPolicy) {
        return _defaultResult(appVersion);
      }

      _lastKnownPolicy = policy;
      return _resultFromPolicy(appVersion, policy);
    } on FormatException catch (error) {
      return VersionCheckResult(
        status: VersionCheckStatus.invalidConfig,
        currentVersion: appVersion.version,
        currentBuild: appVersion.buildNumber,
        minVersion: appVersion.version,
        updateUrl: updateUrl,
        platform: appVersion.platform,
        channel: appVersion.channel,
        failureReason: error.message,
      );
    } catch (error) {
      final cachedPolicy = _lastKnownPolicy;
      if (cachedPolicy != null) {
        return _resultFromPolicy(appVersion, cachedPolicy);
      }
      return VersionCheckResult(
        status: VersionCheckStatus.checkUnavailable,
        currentVersion: appVersion.version,
        currentBuild: appVersion.buildNumber,
        minVersion: appVersion.version,
        updateUrl: updateUrl,
        platform: appVersion.platform,
        channel: appVersion.channel,
        failureReason: error.toString(),
      );
    }
  }

  Future<VersionCheckResult> checkUnavailable() async {
    final appVersion = await _loadAppVersionInfo();
    return VersionCheckResult(
      status: VersionCheckStatus.checkUnavailable,
      currentVersion: appVersion.version,
      currentBuild: appVersion.buildNumber,
      minVersion: appVersion.version,
      updateUrl: updateUrl,
      platform: appVersion.platform,
      channel: appVersion.channel,
    );
  }

  Future<AppVersionInfo> _loadAppVersionInfo() async {
    final info = _packageInfoLoader == null
        ? await PackageInfo.fromPlatform()
        : await _packageInfoLoader();
    return AppVersionInfo.fromPackageInfo(
      packageInfo: info,
      channel: updateChannel,
      platform: _platform ?? currentVersionPlatformKey(),
    );
  }

  Future<ReleaseVersionPolicy?> _loadPolicy() async {
    if (_manifestLoader != null) {
      final manifest = (await _manifestLoader())?.trim();
      if (manifest == null || manifest.isEmpty) {
        return null;
      }
      return _policyFromManifest(manifest);
    }

    if (_configLoader != null) {
      final config = await _configLoader();
      if (config == null) {
        return null;
      }
      return ReleaseVersionPolicy.legacy(
        minimumVersion: config.minVersion,
        updateUrl: config.updateUrl.trim().isEmpty
            ? updateUrl
            : config.updateUrl.trim(),
      );
    }

    final refresh = _fetchAndActivate ?? _remoteConfig?.fetchAndActivate;
    if (_remoteConfig == null && refresh == null) {
      return null;
    }

    await refresh?.call();
    if (_remoteConfig == null) {
      return null;
    }

    final manifest = _remoteConfig
        .getString(rainReleaseManifestRemoteConfigKey)
        .trim();
    if (manifest.isNotEmpty) {
      return _policyFromManifest(manifest);
    }

    final minVersion = _remoteConfig.getString('min_required_version').trim();
    final remoteUpdateUrl = _remoteConfig.getString('update_url').trim();
    if (minVersion.isEmpty && remoteUpdateUrl.isEmpty) {
      return null;
    }
    return ReleaseVersionPolicy.legacy(
      minimumVersion: minVersion,
      updateUrl: remoteUpdateUrl.isEmpty ? updateUrl : remoteUpdateUrl,
    );
  }

  ReleaseVersionPolicy _policyFromManifest(String manifest) {
    final decoded = jsonDecode(manifest);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Rain release manifest must be a JSON map.');
    }
    final schema = decoded['schema'];
    if (schema != 1) {
      throw const FormatException('Unsupported Rain release manifest schema.');
    }
    final channels = decoded['channels'];
    if (channels is! Map<String, dynamic>) {
      throw const FormatException('Rain release manifest missing channels.');
    }
    final channelNode = channels[updateChannel.name];
    if (channelNode == null) {
      return ReleaseVersionPolicy(updateUrl: updateUrl);
    }
    if (channelNode is! Map<String, dynamic>) {
      throw FormatException(
        'Rain release manifest channel ${updateChannel.name} is invalid.',
      );
    }
    final platformKey = _platform ?? currentVersionPlatformKey();
    final platformNode = channelNode[platformKey];
    if (platformNode == null) {
      return ReleaseVersionPolicy(updateUrl: updateUrl);
    }
    if (platformNode is! Map<String, dynamic>) {
      throw FormatException(
        'Rain release manifest platform $platformKey is invalid.',
      );
    }
    return ReleaseVersionPolicy.fromJson(
      platformNode,
      fallbackUpdateUrl: updateUrl,
    );
  }

  VersionCheckResult _defaultResult(AppVersionInfo appVersion) {
    return VersionCheckResult(
      status: VersionCheckStatus.current,
      currentVersion: appVersion.version,
      currentBuild: appVersion.buildNumber,
      minVersion: appVersion.version,
      updateUrl: updateUrl,
      platform: appVersion.platform,
      channel: appVersion.channel,
    );
  }

  VersionCheckResult _resultFromPolicy(
    AppVersionInfo appVersion,
    ReleaseVersionPolicy policy,
  ) {
    final requiresUpdate = _isPolicyNewerThanApp(
      appVersion,
      version: policy.minimumVersion,
      build: policy.minimumBuild,
    );
    final hasOptionalUpdate = _isPolicyNewerThanApp(
      appVersion,
      version: policy.latestVersion,
      build: policy.latestBuild,
    );

    return VersionCheckResult(
      status: requiresUpdate
          ? VersionCheckStatus.updateRequired
          : hasOptionalUpdate
          ? VersionCheckStatus.optionalUpdateAvailable
          : VersionCheckStatus.current,
      currentVersion: appVersion.version,
      currentBuild: appVersion.buildNumber,
      minVersion: policy.minimumVersion ?? appVersion.version,
      minimumBuild: policy.minimumBuild,
      latestVersion: policy.latestVersion,
      latestBuild: policy.latestBuild,
      updateUrl: policy.updateUrl.trim().isEmpty
          ? updateUrl
          : policy.updateUrl.trim(),
      platform: appVersion.platform,
      channel: appVersion.channel,
      notes: policy.notes,
      publishedAt: policy.publishedAt,
    );
  }

  bool _isPolicyNewerThanApp(
    AppVersionInfo appVersion, {
    required String? version,
    required int? build,
  }) {
    if (version == null && build == null) {
      return false;
    }
    final versionComparison = compareVersionStrings(
      appVersion.version,
      version ?? appVersion.version,
    );
    if (versionComparison < 0) {
      return true;
    }
    if (versionComparison > 0) {
      return false;
    }
    final targetBuild = build;
    if (targetBuild == null) {
      return false;
    }
    return appVersion.buildNumber < targetBuild;
  }
}

int compareVersionStrings(String current, String target) {
  final currentParts = _parseVersion(current);
  final targetParts = _parseVersion(target);
  for (var index = 0; index < 3; index += 1) {
    final currentValue = currentParts[index];
    final targetValue = targetParts[index];
    if (currentValue > targetValue) {
      return 1;
    }
    if (currentValue < targetValue) {
      return -1;
    }
  }
  return 0;
}

String currentVersionPlatformKey() {
  if (kIsWeb) {
    return 'web';
  }
  return switch (defaultTargetPlatform) {
    TargetPlatform.android => 'android',
    TargetPlatform.windows => 'windows',
    TargetPlatform.macOS => 'macos',
    TargetPlatform.linux => 'linux',
    TargetPlatform.iOS => 'ios',
    TargetPlatform.fuchsia => 'fuchsia',
  };
}

List<int> _parseVersion(String value) {
  final version = value.split('+').first.trim();
  final parts = version.split('.');
  return <int>[
    for (var index = 0; index < 3; index += 1)
      index < parts.length ? int.tryParse(parts[index]) ?? 0 : 0,
  ];
}

String? _optionalString(Object? value) {
  final text = value?.toString().trim();
  if (text == null || text.isEmpty) {
    return null;
  }
  return text;
}

int? _optionalInt(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  final text = value?.toString().trim();
  if (text == null || text.isEmpty) {
    return null;
  }
  return int.tryParse(text);
}
