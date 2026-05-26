import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:rain/infrastructure/services/force_update_service.dart';

void main() {
  test('version comparison handles patch and build precedence', () {
    expect(compareVersionStrings('1.2.3+4', '1.2.3'), 0);
    expect(compareVersionStrings('1.2.3', '1.2.4'), -1);
    expect(compareVersionStrings('1.3.0', '1.2.99'), 1);
    expect(compareVersionStrings('bad', '0.0.1'), -1);
  });

  test('custom config loader enforces configured min version', () async {
    final service = ForceUpdateService(
      remoteConfig: null,
      updateUrl: 'https://example.com/update',
      configLoader: () async => const ForceUpdateConfig(
        minVersion: '1.2.4',
        updateUrl: 'https://example.com/releases',
      ),
      packageInfoLoader: () async => PackageInfo(
        appName: 'Rain',
        packageName: 'com.rainapp.rain',
        version: '1.2.3',
        buildNumber: '123',
        buildSignature: '',
      ),
    );

    final result = await service.check();

    expect(result.status, ForceUpdateStatus.updateRequired);
    expect(result.requiresUpdate, isTrue);
    expect(result.currentVersion, '1.2.3');
    expect(result.minVersion, '1.2.4');
    expect(result.updateUrl, 'https://example.com/releases');
  });

  test('manifest loader selects channel and platform policy', () async {
    final service = ForceUpdateService(
      remoteConfig: null,
      updateUrl: 'https://example.com/update',
      updateChannel: AppUpdateChannel.demo,
      platform: 'android',
      manifestLoader: () async => _manifest(
        channel: 'demo',
        platform: 'android',
        latestVersion: '1.2.4',
        latestBuild: 124,
        minimumVersion: '1.2.0',
        minimumBuild: 120,
      ),
      packageInfoLoader: () async =>
          _packageInfo(version: '1.2.3', buildNumber: '123'),
    );

    final result = await service.check();

    expect(result.status, ForceUpdateStatus.optionalUpdateAvailable);
    expect(result.hasOptionalUpdate, isTrue);
    expect(result.requiresUpdate, isFalse);
    expect(result.latestVersion, '1.2.4');
    expect(result.latestBuild, 124);
    expect(result.minVersion, '1.2.0');
    expect(result.minimumBuild, 120);
    expect(result.platform, 'android');
    expect(result.channel, AppUpdateChannel.demo);
  });

  test('required update wins over optional update', () async {
    final service = ForceUpdateService(
      remoteConfig: null,
      updateUrl: 'https://example.com/update',
      updateChannel: AppUpdateChannel.stable,
      platform: 'windows',
      manifestLoader: () async => _manifest(
        channel: 'stable',
        platform: 'windows',
        latestVersion: '1.3.0',
        latestBuild: 130,
        minimumVersion: '1.2.4',
        minimumBuild: 124,
      ),
      packageInfoLoader: () async =>
          _packageInfo(version: '1.2.3', buildNumber: '123'),
    );

    final result = await service.check();

    expect(result.status, ForceUpdateStatus.updateRequired);
    expect(result.requiresUpdate, isTrue);
    expect(result.hasOptionalUpdate, isFalse);
  });

  test('same semantic version uses build number for update checks', () async {
    final service = ForceUpdateService(
      remoteConfig: null,
      updateUrl: 'https://example.com/update',
      platform: 'android',
      manifestLoader: () async => _manifest(
        channel: 'stable',
        platform: 'android',
        latestVersion: '1.2.3',
        latestBuild: 124,
        minimumVersion: '1.2.3',
        minimumBuild: 120,
      ),
      packageInfoLoader: () async =>
          _packageInfo(version: '1.2.3', buildNumber: '123'),
    );

    final result = await service.check();

    expect(result.status, ForceUpdateStatus.optionalUpdateAvailable);
    expect(result.displayCurrentBuild, '123');
    expect(result.displayLatestBuild, '124');
  });

  test('invalid manifest reports invalid config without crashing', () async {
    final service = ForceUpdateService(
      remoteConfig: null,
      updateUrl: 'https://example.com/update',
      manifestLoader: () async => '{"schema":2}',
      packageInfoLoader: () async =>
          _packageInfo(version: '1.2.3', buildNumber: '123'),
    );

    final result = await service.check();

    expect(result.status, ForceUpdateStatus.invalidConfig);
    expect(result.requiresUpdate, isFalse);
    expect(result.failureReason, isNotEmpty);
  });

  test(
    'force update checks report unavailable without cached config',
    () async {
      final service = ForceUpdateService(
        remoteConfig: null,
        updateUrl: 'https://example.com/update',
        packageInfoLoader: () async => PackageInfo(
          appName: 'Rain',
          packageName: 'com.rainapp.rain',
          version: '1.2.3',
          buildNumber: '123',
          buildSignature: '',
        ),
        fetchAndActivate: () async {
          throw StateError('network down');
        },
      );

      final result = await service.check();

      expect(result.status, ForceUpdateStatus.checkUnavailable);
      expect(result.requiresUpdate, isFalse);
      expect(result.currentVersion, '1.2.3');
      expect(result.minVersion, '1.2.3');
      expect(result.updateUrl, 'https://example.com/update');
    },
  );

  test(
    'force update checks reuse last known config when refresh throws',
    () async {
      var shouldThrow = false;
      final service = ForceUpdateService(
        remoteConfig: null,
        updateUrl: 'https://example.com/update',
        packageInfoLoader: () async => PackageInfo(
          appName: 'Rain',
          packageName: 'com.rainapp.rain',
          version: '1.2.3',
          buildNumber: '123',
          buildSignature: '',
        ),
        configLoader: () async {
          if (shouldThrow) {
            throw StateError('network down');
          }
          return const ForceUpdateConfig(
            minVersion: '1.2.4',
            updateUrl: 'https://example.com/releases',
          );
        },
      );

      final first = await service.check();
      shouldThrow = true;
      final second = await service.check();

      expect(first.status, ForceUpdateStatus.updateRequired);
      expect(second.status, ForceUpdateStatus.updateRequired);
      expect(second.minVersion, '1.2.4');
      expect(second.updateUrl, 'https://example.com/releases');
    },
  );
}

PackageInfo _packageInfo({
  required String version,
  required String buildNumber,
}) {
  return PackageInfo(
    appName: 'Rain',
    packageName: 'com.rainapp.rain',
    version: version,
    buildNumber: buildNumber,
    buildSignature: '',
  );
}

String _manifest({
  required String channel,
  required String platform,
  required String latestVersion,
  required int latestBuild,
  required String minimumVersion,
  required int minimumBuild,
}) {
  return '''
{
  "schema": 1,
  "channels": {
    "$channel": {
      "$platform": {
        "latestVersion": "$latestVersion",
        "latestBuild": $latestBuild,
        "minimumVersion": "$minimumVersion",
        "minimumBuild": $minimumBuild,
        "updateUrl": "https://example.com/releases",
        "notes": "Release notes",
        "publishedAt": 1770000000000
      }
    }
  }
}
''';
}
