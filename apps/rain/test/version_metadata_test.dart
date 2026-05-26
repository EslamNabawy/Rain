import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('pubspec app version has numeric build metadata', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final match = RegExp(
      r'^version:\s*(\d+)\.(\d+)\.(\d+)\+(\d+)\s*$',
      multiLine: true,
    ).firstMatch(pubspec);

    expect(match, isNotNull);
    expect(int.parse(match!.group(4)!), greaterThan(0));
  });

  test('demo dart defines declare demo update channel', () {
    final raw = File('tool/dart_defines.example.json').readAsStringSync();
    final json = jsonDecode(raw) as Map<String, dynamic>;

    expect(json['RAIN_UPDATE_CHANNEL'], 'demo');
    expect(json['RAIN_UPDATE_URL'], isA<String>());
  });
}
