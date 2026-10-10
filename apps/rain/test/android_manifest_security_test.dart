import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android manifest disables auto-backup of the local database', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();

    expect(manifest, contains('android:allowBackup="false"'));
    expect(
      manifest,
      contains('android:dataExtractionRules="@xml/data_extraction_rules"'),
    );
  });

  test('data extraction rules exclude every app data domain', () {
    final rules = File(
      'android/app/src/main/res/xml/data_extraction_rules.xml',
    ).readAsStringSync();

    for (final section in <String>['cloud-backup', 'device-transfer']) {
      expect(rules, contains('<$section>'), reason: section);
    }
    for (final domain in <String>['root', 'file', 'database', 'sharedpref']) {
      expect(rules, contains('<exclude domain="$domain"'), reason: domain);
    }
  });
}
