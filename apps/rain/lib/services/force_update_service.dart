import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:package_info_plus/package_info_plus.dart';

class ForceUpdateConfig {
  const ForceUpdateConfig({required this.minVersion, required this.updateUrl});

  final String minVersion;
  final String updateUrl;
}

typedef ForceUpdateConfigLoader = Future<ForceUpdateConfig?> Function();

enum ForceUpdateStatus { current, updateRequired, checkUnavailable }

class ForceUpdateResult {
  const ForceUpdateResult({
    required this.status,
    required this.currentVersion,
    required this.minVersion,
    required this.updateUrl,
  });

  final ForceUpdateStatus status;
  final String currentVersion;
  final String minVersion;
  final String updateUrl;

  bool get requiresUpdate => status == ForceUpdateStatus.updateRequired;
}

class ForceUpdateService {
  ForceUpdateService({
    required FirebaseRemoteConfig? remoteConfig,
    required this.updateUrl,
    ForceUpdateConfigLoader? configLoader,
    Future<PackageInfo> Function()? packageInfoLoader,
    Future<bool> Function()? fetchAndActivate,
  }) : _remoteConfig = remoteConfig,
       _configLoader = configLoader,
       _packageInfoLoader = packageInfoLoader,
       _fetchAndActivate = fetchAndActivate;

  final FirebaseRemoteConfig? _remoteConfig;
  final String updateUrl;
  final ForceUpdateConfigLoader? _configLoader;
  final Future<PackageInfo> Function()? _packageInfoLoader;
  final Future<bool> Function()? _fetchAndActivate;
  ForceUpdateConfig? _lastKnownConfig;

  Future<ForceUpdateResult> check() async {
    final info = _packageInfoLoader == null
        ? await PackageInfo.fromPlatform()
        : await _packageInfoLoader();

    try {
      final config = await _loadConfig();
      if (config == null) {
        return _defaultResult(info.version);
      }

      _lastKnownConfig = config;
      return _resultFromConfig(info.version, config);
    } catch (_) {
      final cachedConfig = _lastKnownConfig;
      if (cachedConfig != null) {
        return _resultFromConfig(info.version, cachedConfig);
      }
      return ForceUpdateResult(
        status: ForceUpdateStatus.checkUnavailable,
        currentVersion: info.version,
        minVersion: info.version,
        updateUrl: updateUrl,
      );
    }
  }

  Future<ForceUpdateConfig?> _loadConfig() async {
    if (_configLoader != null) {
      return _configLoader();
    }

    final refresh = _fetchAndActivate ?? _remoteConfig?.fetchAndActivate;
    if (_remoteConfig == null && refresh == null) {
      return null;
    }

    await refresh?.call();
    if (_remoteConfig == null) {
      return null;
    }

    return ForceUpdateConfig(
      minVersion: _remoteConfig.getString('min_required_version').trim(),
      updateUrl: _remoteConfig.getString('update_url').trim(),
    );
  }

  ForceUpdateResult _defaultResult(String currentVersion) {
    return ForceUpdateResult(
      status: ForceUpdateStatus.current,
      currentVersion: currentVersion,
      minVersion: currentVersion,
      updateUrl: updateUrl,
    );
  }

  ForceUpdateResult _resultFromConfig(
    String currentVersion,
    ForceUpdateConfig config,
  ) {
    final minVersion = config.minVersion.trim();
    final remoteUpdateUrl = config.updateUrl.trim();
    final requiresUpdate =
        minVersion.isNotEmpty && !_isVersionAtLeast(currentVersion, minVersion);
    return ForceUpdateResult(
      status: requiresUpdate
          ? ForceUpdateStatus.updateRequired
          : ForceUpdateStatus.current,
      currentVersion: currentVersion,
      minVersion: minVersion.isEmpty ? currentVersion : minVersion,
      updateUrl: remoteUpdateUrl.isEmpty ? updateUrl : remoteUpdateUrl,
    );
  }

  bool _isVersionAtLeast(String current, String minimum) {
    final currentParts = current
        .split('.')
        .map(_parseVersionPart)
        .toList(growable: false);
    final minimumParts = minimum
        .split('.')
        .map(_parseVersionPart)
        .toList(growable: false);
    final length = currentParts.length > minimumParts.length
        ? currentParts.length
        : minimumParts.length;

    for (var index = 0; index < length; index++) {
      final currentValue = index < currentParts.length
          ? currentParts[index]
          : 0;
      final minimumValue = index < minimumParts.length
          ? minimumParts[index]
          : 0;
      if (currentValue > minimumValue) {
        return true;
      }
      if (currentValue < minimumValue) {
        return false;
      }
    }
    return true;
  }

  int _parseVersionPart(String value) {
    return int.tryParse(value) ?? 0;
  }
}
