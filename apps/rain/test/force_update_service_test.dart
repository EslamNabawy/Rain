import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:rain/services/force_update_service.dart';

void main() {
  test('custom config loader enforces the Supabase min version', () async {
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
