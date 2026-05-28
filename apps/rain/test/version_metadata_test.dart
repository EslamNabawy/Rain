import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

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
