import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:package_info_plus/package_info_plus.dart';

class ForceUpdateResult {
  const ForceUpdateResult({
    required this.requiresUpdate,
    required this.currentVersion,
    required this.minVersion,
    required this.updateUrl,
  });

  final bool requiresUpdate;
  final String currentVersion;
  final String minVersion;
  final String updateUrl;
}

class ForceUpdateService {
  const ForceUpdateService({
    required FirebaseRemoteConfig? remoteConfig,
    required this.updateUrl,
  }) : _remoteConfig = remoteConfig;

  final FirebaseRemoteConfig? _remoteConfig;
  final String updateUrl;

  Future<ForceUpdateResult> check() async {
    final info = await PackageInfo.fromPlatform();
    if (_remoteConfig == null) {
      return ForceUpdateResult(
        requiresUpdate: false,
        currentVersion: info.version,
        minVersion: info.version,
        updateUrl: updateUrl,
      );
    }

    await _remoteConfig.fetchAndActivate();
    final minVersion = _remoteConfig.getString('min_required_version');
    return ForceUpdateResult(
      requiresUpdate: !_isVersionAtLeast(info.version, minVersion),
      currentVersion: info.version,
      minVersion: minVersion,
      updateUrl: updateUrl,
    );
  }

  bool _isVersionAtLeast(String current, String minimum) {
    final currentParts = current.split('.').map(int.parse).toList(growable: false);
    final minimumParts = minimum.split('.').map(int.parse).toList(growable: false);
    final length = currentParts.length > minimumParts.length
        ? currentParts.length
        : minimumParts.length;

    for (var index = 0; index < length; index++) {
      final currentValue = index < currentParts.length ? currentParts[index] : 0;
      final minimumValue = index < minimumParts.length ? minimumParts[index] : 0;
      if (currentValue > minimumValue) {
        return true;
      }
      if (currentValue < minimumValue) {
        return false;
      }
    }
    return true;
  }
}
