import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:rain/infrastructure/services/force_update_service.dart';

void main() {
  test('pubspec app version has numeric build metadata', () {
    final match = _pubspecVersionMatch();

    expect(match, isNotNull);
    expect(int.parse(match!.group(4)!), greaterThan(0));
  });

  test('release manifest example advertises current app build or newer', () {
    final match = _pubspecVersionMatch()!;
    final version = '${match.group(1)}.${match.group(2)}.${match.group(3)}';
    final build = int.parse(match.group(4)!);
    final raw = File(
      '../../docs/releases/rain_release_manifest_v1.example.json',
    ).readAsStringSync();
    final manifest = jsonDecode(raw) as Map<String, dynamic>;
    final channels = manifest['channels'] as Map<String, dynamic>;

    for (final channel in <String>['stable', 'demo']) {
      final platforms = channels[channel] as Map<String, dynamic>;
      for (final platform in <String>['android', 'windows']) {
        final policy = platforms[platform] as Map<String, dynamic>;

        expect(policy['latestVersion'], version);
        expect(policy['latestBuild'], greaterThanOrEqualTo(build));
      }
    }
  });

  test('remote config template advertises current app build or newer', () {
    final match = _pubspecVersionMatch()!;
    final version = '${match.group(1)}.${match.group(2)}.${match.group(3)}';
    final build = int.parse(match.group(4)!);
    final raw = File(
      '../../backend/firebase/remoteconfig.template.json',
    ).readAsStringSync();
    final template = jsonDecode(raw) as Map<String, dynamic>;
    final parameters = template['parameters'] as Map<String, dynamic>;
    final manifestValue =
        ((parameters['rain_release_manifest_v1']
                    as Map<String, dynamic>)['defaultValue']
                as Map<String, dynamic>)['value']
            as String;
    final manifest = jsonDecode(manifestValue) as Map<String, dynamic>;
    final channels = manifest['channels'] as Map<String, dynamic>;

    for (final channel in <String>['stable', 'demo']) {
      final platforms = channels[channel] as Map<String, dynamic>;
      for (final platform in <String>['android', 'windows']) {
        final policy = platforms[platform] as Map<String, dynamic>;

        expect(policy['latestVersion'], version);
        expect(policy['latestBuild'], greaterThanOrEqualTo(build));
        expect(policy['minimumVersion'], version);
        expect(policy['minimumBuild'], greaterThanOrEqualTo(build));
      }
    }
  });

  test('remote config template warns the previous 1.0.6 build 7 app', () async {
    final manifest = _remoteConfigManifest();

    for (final channel in AppUpdateChannel.values) {
      for (final platform in <String>['android', 'windows']) {
        final service = ForceUpdateService(
          remoteConfig: null,
          updateUrl: 'https://github.com/EslamNabawy/Rain/releases',
          updateChannel: channel,
          platform: platform,
          manifestLoader: () async => manifest,
          packageInfoLoader: () async => PackageInfo(
            appName: 'Rain',
            packageName: 'com.rainapp.rain',
            version: '1.0.6',
            buildNumber: '7',
            buildSignature: '',
          ),
        );

        final result = await service.check();

        expect(
          result.status,
          ForceUpdateStatus.updateRequired,
          reason:
              'Remote Config must warn previous 1.0.6+7 $channel/$platform '
              'installs after a newer test build is published.',
        );
      }
    }
  });

  test('legacy remote config minimum version matches current app version', () {
    final match = _pubspecVersionMatch()!;
    final version = '${match.group(1)}.${match.group(2)}.${match.group(3)}';
    final raw = File(
      '../../backend/firebase/remoteconfig.template.json',
    ).readAsStringSync();
    final template = jsonDecode(raw) as Map<String, dynamic>;
    final parameters = template['parameters'] as Map<String, dynamic>;
    final minRequiredVersion =
        ((parameters['min_required_version']
                    as Map<String, dynamic>)['defaultValue']
                as Map<String, dynamic>)['value']
            as String;

    expect(minRequiredVersion, version);
  });

  test('demo dart defines declare demo update channel', () {
    final raw = File('tool/dart_defines.example.json').readAsStringSync();
    final json = jsonDecode(raw) as Map<String, dynamic>;

    expect(json['RAIN_UPDATE_CHANNEL'], 'demo');
    expect(json['RAIN_UPDATE_URL'], isA<String>());
  });
}

RegExpMatch? _pubspecVersionMatch() {
  final pubspec = File('pubspec.yaml').readAsStringSync();
  return RegExp(
    r'^version:\s*(\d+)\.(\d+)\.(\d+)\+(\d+)\s*$',
    multiLine: true,
  ).firstMatch(pubspec);
}

String _remoteConfigManifest() {
  final raw = File(
    '../../backend/firebase/remoteconfig.template.json',
  ).readAsStringSync();
  final template = jsonDecode(raw) as Map<String, dynamic>;
  final parameters = template['parameters'] as Map<String, dynamic>;
  return ((parameters['rain_release_manifest_v1']
              as Map<String, dynamic>)['defaultValue']
          as Map<String, dynamic>)['value']
      as String;
}
