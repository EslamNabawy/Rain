import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android launch and normal themes use the dark splash background', () {
    final styleFiles = <String>[
      'android/app/src/main/res/values/styles.xml',
      'android/app/src/main/res/values-night/styles.xml',
    ];

    for (final path in styleFiles) {
      final xml = File(path).readAsStringSync();
      expect(
        _styleWindowBackground(xml, 'LaunchTheme'),
        '@drawable/launch_background',
        reason: path,
      );
      expect(
        _styleWindowBackground(xml, 'NormalTheme'),
        '@drawable/launch_background',
        reason: path,
      );
    }
  });

  test('Android launch background stays aligned with Flutter splash color', () {
    final drawableFiles = <String>[
      'android/app/src/main/res/drawable/launch_background.xml',
      'android/app/src/main/res/drawable-v21/launch_background.xml',
    ];

    for (final path in drawableFiles) {
      final xml = File(path).readAsStringSync();
      expect(xml, contains('android:color="#061017"'), reason: path);
      expect(xml, contains('@drawable/rain_splash_mark'), reason: path);
    }
  });

  test('Android 12 splash styles use the Rain mark on the app background', () {
    for (final path in <String>[
      'android/app/src/main/res/values-v31/styles.xml',
      'android/app/src/main/res/values-night-v31/styles.xml',
    ]) {
      final xml = File(path).readAsStringSync();
      expect(
        xml,
        contains('name="android:windowSplashScreenBackground">#061017<'),
        reason: path,
      );
      expect(
        xml,
        contains(
          'name="android:windowSplashScreenAnimatedIcon">@drawable/rain_splash_mark<',
        ),
        reason: path,
      );
      expect(
        _styleWindowBackground(xml, 'NormalTheme'),
        '@drawable/launch_background',
        reason: path,
      );
    }
  });

  test('Rain splash mark bitmap exists', () {
    expect(
      File(
        'android/app/src/main/res/drawable-nodpi/rain_splash_mark.png',
      ).existsSync(),
      isTrue,
    );
  });
}

String? _styleWindowBackground(String xml, String styleName) {
  final styleMatch = RegExp(
    '<style\\s+name="$styleName"[^>]*>([\\s\\S]*?)</style>',
  ).firstMatch(xml);
  if (styleMatch == null) {
    return null;
  }

  final itemMatch = RegExp(
    '<item\\s+name="android:windowBackground">([^<]+)</item>',
  ).firstMatch(styleMatch.group(1)!);
  return itemMatch?.group(1)?.trim();
}
