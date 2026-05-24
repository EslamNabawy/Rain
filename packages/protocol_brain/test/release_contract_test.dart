import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _repoFile(String relativePath) {
  final workspaceRoot = _workspaceRoot();
  return File.fromUri(
    workspaceRoot.uri.resolve(relativePath),
  ).readAsStringSync().replaceAll('\r\n', '\n');
}

Directory _workspaceRoot() {
  var directory = Directory.current;
  while (true) {
    final pubspec = File.fromUri(directory.uri.resolve('pubspec.yaml'));
    if (pubspec.existsSync() &&
        pubspec.readAsStringSync().contains('name: rain_workspace')) {
      return directory;
    }
    final parent = directory.parent;
    if (parent.path == directory.path) {
      throw StateError('Could not locate Rain workspace root.');
    }
    directory = parent;
  }
}

void main() {
  test('release script requires project-owned TURN release defines', () {
    final script = _repoFile('scripts/build_release.ps1');

    expect(script, contains('[string]\$DartDefinesFile'));
    expect(script, contains('[switch]\$AllowPublicTurnForDemo'));
    expect(script, contains('[switch]\$UseDemoAndroidSigningKey'));
    expect(
      script,
      contains(
        'Release builds require -DartDefinesFile with project-owned TURN servers.',
      ),
    );
    expect(
      script,
      contains(
        'RAIN_SIGNALING_ENCRYPTION_KEY is required in release dart defines.',
      ),
    );
    expect(
      script,
      contains('RAIN_SIGNALING_ENCRYPTION_KEY must be at least 32 characters.'),
    );
    expect(
      script,
      contains(
        'Production release builds must not use the demo signaling encryption key.',
      ),
    );
    expect(script, contains('Assert-ReleaseDartDefines -Path \$resolved'));
    expect(
      script,
      contains('RAIN_ICE_SERVERS is required in release dart defines.'),
    );
    expect(
      script,
      contains('RAIN_ICE_SERVERS must be a JSON array of ICE server objects.'),
    );
    expect(script, contains('RAIN_ICE_SERVERS must include ICE server urls.'));
    expect(
      script,
      contains('Release builds must not use tool\\dart_defines.local.json'),
    );
    expect(
      script,
      isNot(
        contains(
          'return @("--dart-define-from-file=tool/dart_defines.local.json")',
        ),
      ),
    );
    expect(
      script,
      contains('Release builds must not use OpenRelay/public TURN servers.'),
    );
    expect(
      script,
      contains(
        'OpenRelay/public TURN is enabled for demo release artifacts only.',
      ),
    );
    expect(script, contains('RAIN_ALLOW_PUBLIC_TURN'));
    expect(
      script,
      contains(
        'Release builds require RAIN_TURN_BROKER_URL or at least one project-owned TURN/TURNS URL in RAIN_ICE_SERVERS.',
      ),
    );
    expect(script, contains('Production release uses TURN credential broker:'));
    expect(
      script,
      contains('Release TURN servers must include username and credential.'),
    );
    expect(
      script,
      contains(
        'Every production TURN/TURNS server entry must include username and credential.',
      ),
    );
    expect(
      script,
      contains(
        'Production RAIN_ICE_SERVERS must include a turn: UDP endpoint.',
      ),
    );
    expect(
      script,
      contains(
        'Production RAIN_ICE_SERVERS must include a turn: TCP endpoint.',
      ),
    );
    expect(
      script,
      contains(
        'Production RAIN_ICE_SERVERS must include a turns: TCP/TLS endpoint.',
      ),
    );
    expect(script, contains('Assert-AndroidReleaseSigning'));
    expect(
      script,
      contains(
        'Demo Android signing is only allowed with -AllowPublicTurnForDemo.',
      ),
    );
    expect(script, contains('Resolve-KeytoolPath'));
    expect(script, contains('JAVA_HOME'));
    expect(script, contains('\$name is required for release signing.'));
    expect(script, contains('RAIN_RELEASE_STORE_FILE does not exist:'));
    expect(script, contains('\$LASTEXITCODE -ne 0'));
  });

  test('Android release signing is required and never debug-signed', () {
    final gradle = _repoFile('apps/rain/android/app/build.gradle.kts');

    expect(gradle, contains('plugins {'));
    expect(gradle, contains('android {'));
    expect(gradle, contains('RAIN_RELEASE_STORE_FILE'));
    expect(gradle, contains('RAIN_RELEASE_STORE_PASSWORD'));
    expect(gradle, contains('RAIN_RELEASE_KEY_ALIAS'));
    expect(gradle, contains('RAIN_RELEASE_KEY_PASSWORD'));
    expect(gradle, contains('signingConfigs.getByName("release")'));
    expect(gradle, contains('isReleaseBuild'));
    expect(gradle, isNot(contains('signingConfigs.getByName("debug")')));
    expect(gradle, isNot(contains('Signing with the debug keys')));
  });

  test('Android manifest keeps call permissions install-safe', () {
    final manifest = _repoFile(
      'apps/rain/android/app/src/main/AndroidManifest.xml',
    );
    final applicationIndex = manifest.indexOf('<application');

    expect(applicationIndex, greaterThan(0));
    for (final feature in <String>[
      '<uses-feature android:name="android.hardware.camera" android:required="false" />',
      '<uses-feature android:name="android.hardware.camera.autofocus" android:required="false" />',
    ]) {
      expect(manifest, contains(feature));
      expect(manifest.indexOf(feature), lessThan(applicationIndex));
    }

    for (final permission in <String>[
      'android.permission.CAMERA',
      'android.permission.RECORD_AUDIO',
      'android.permission.MODIFY_AUDIO_SETTINGS',
      'android.permission.ACCESS_NETWORK_STATE',
      'android.permission.CHANGE_NETWORK_STATE',
    ]) {
      final entry = '<uses-permission android:name="$permission" />';
      expect(manifest, contains(entry));
      expect(manifest.indexOf(entry), lessThan(applicationIndex));
    }

    expect(manifest, isNot(contains('android:required="true"')));
    expect(manifest, isNot(contains('android.permission.BLUETOOTH')));
    expect(manifest, isNot(contains('android.permission.BLUETOOTH_CONNECT')));
  });

  test('release workflow creates sanitized defines and signing inputs', () {
    final workflow = _repoFile('.github/workflows/release.yml');

    expect(workflow, contains('RAIN_RELEASE_KEYSTORE_BASE64'));
    expect(workflow, contains('RAIN_RELEASE_DART_DEFINES_JSON'));
    expect(workflow, contains('-DartDefinesFile'));
    expect(workflow, contains('RAIN_RELEASE_STORE_FILE'));
  });

  test('demo dart defines include signaling encryption key', () {
    final defines = _repoFile('apps/rain/tool/dart_defines.example.json');

    expect(defines, contains('RAIN_SIGNALING_ENCRYPTION_KEY'));
    expect(
      defines,
      contains('rain-demo-signaling-encryption-key-v1-change-me'),
    );
  });

  test('stable test pair script builds shared-key Windows and v7a APK', () {
    final script = _repoFile('scripts/build_stable_test_pair.ps1');

    expect(script, contains('Builds a local Rain test pair'));
    expect(script, contains('New-SignalingKey'));
    expect(script, contains('Stable test builds must not use the demo'));
    expect(script, contains('RAIN_SIGNALING_ENCRYPTION_KEY'));
    expect(script, contains('RAIN_ALLOW_PUBLIC_TURN'));
    expect(script, contains('--dart-define-from-file='));
    expect(script, contains("('build', 'windows', '--release'"));
    expect(script, contains('flutter_webrtc_plugin.dll'));
    expect(script, contains('libwebrtc.dll'));
    expect(script, contains('Use-LocalDebugSigningKey'));
    expect(script, contains('androiddebugkey'));
    expect(script, contains("'apk',"));
    expect(script, contains('--split-per-abi'));
    expect(script, contains("'android-arm'"));
    expect(script, contains('app-armeabi-v7a-release.apk'));
    expect(script, contains('Assert-ApkContainsOnlyArmV7'));
    expect(script, contains("only armeabi-v7a"));
    expect(script, isNot(contains('android-arm64')));
    expect(script, isNot(contains('app-arm64-v8a-release.apk')));
  });

  test('stable test build docs preserve shared key release rule', () {
    final docs = _repoFile('docs/stable-test-build.md');

    expect(
      docs,
      contains(
        'Windows and the APK pair must be built with the same non-demo `RAIN_SIGNALING_ENCRYPTION_KEY`',
      ),
    );
    expect(docs, contains('scripts\\build_stable_test_pair.ps1'));
    expect(docs, contains('app-armeabi-v7a-release.apk'));
    expect(docs, contains('build\\windows\\x64\\runner\\Release\\rain.exe'));
    expect(docs, contains('locally test-signed'));
    expect(docs, contains('not store distribution'));
    expect(docs, contains('Video calls require camera and microphone access'));
    expect(
      docs,
      contains('allow the camera and microphone permission prompts'),
    );
    expect(
      docs,
      contains(
        'Windows: Settings > Privacy & security must allow Rain to use the camera and microphone.',
      ),
    );
    expect(docs, contains('dart run melos run analyze'));
    expect(docs, contains('dart run melos run test'));
  });

  test('release script packages only ARM v7 and ARM v8/v9 Android APKs', () {
    final script = _repoFile('scripts/build_release.ps1');

    expect(script, contains('--split-per-abi'));
    expect(script, contains('Assert-AndroidApkContainsNativeRuntimes'));
    expect(script, contains('libsqlite3.so'));
    expect(script, contains('libjingle_peerconnection_so.so'));
    expect(script, contains('Rain-release'));
    expect(script, contains('Rain-Demo'));
    expect(script, contains('ARM v7 devices (armeabi-v7a)'));
    expect(script, contains('ARM v8/v9 devices (arm64-v8a)'));
    expect(script, contains('Rain-Demo-Android-ARM-v7a-Build.apk'));
    expect(script, contains('Rain-Demo-Android-ARM-v8-v9-Build.apk'));
    expect(script, contains('Rain-Demo-Windows-x64-Build'));
    expect(script, contains('[string]\$AndroidArtifactSet = \'all\''));
    expect(script, contains('android-arm,android-arm64'));
    expect(script, contains('\$androidArtifactPrefix-android-armeabi-v7a.apk'));
    expect(script, contains('android-arm64'));
    expect(script, contains('\$androidArtifactPrefix-android-arm64-v8a.apk'));
    expect(script, isNot(contains('Rain-Demo-Android-Universal-Build.apk')));
    expect(script, isNot(contains('Rain-Demo-Android-x86_64-Build.apk')));
    expect(script, isNot(contains('android-x86_64.apk')));
  });

  test('Windows release packaging includes Dart native assets', () {
    final script = _repoFile('scripts/build_release.ps1');

    expect(script, contains('Copy-WindowsNativeAssets'));
    expect(script, contains('Assert-WindowsRuntimeBundle'));
    expect(script, contains('Assert-WindowsNativeAssetsPackaged'));
    expect(script, contains('Assert-WindowsSqliteExports'));
    expect(script, contains('Resolve-DumpbinPath'));
    expect(script, contains('sqlite3_temp_directory'));
    expect(script, contains('rain.exe'));
    expect(script, contains('flutter_windows.dll'));
    expect(script, contains('flutter_webrtc_plugin.dll'));
    expect(script, contains('libwebrtc.dll'));
    expect(script, contains('data'));
    expect(script, contains('Get-WindowsNativeAssetNames'));
    expect(script, contains(r"build\native_assets\windows"));
    expect(script, contains(r"data\flutter_assets\NativeAssetsManifest.json"));
    expect(script, contains("entry[0] -ne 'absolute'"));
    expect(script, contains('Windows native asset source not found:'));
    expect(
      script,
      contains('Windows native asset not found in portable output:'),
    );
    expect(
      script,
      contains(
        'Copy-WindowsNativeAssets -ProjectRoot \$appsRoot -DestinationRoot \$windowsPortableDir',
      ),
    );
  });

  test('Windows release packaging removes non-runtime linker artifacts', () {
    final script = _repoFile('scripts/build_release.ps1');

    expect(script, contains('Remove-WindowsLinkerArtifacts'));
    expect(script, contains("'.exp', '.lib'"));
    expect(
      script,
      contains(
        'Remove-WindowsLinkerArtifacts -DestinationRoot \$windowsPortableDir',
      ),
    );
  });

  test(
    'CI and release workflows verify only Android ARM v7 and ARM v8/v9 APKs',
    () {
      final workflows = <String>[
        _repoFile('.github/workflows/ci.yml'),
        _repoFile('.github/workflows/release.yml'),
      ];

      for (final workflow in workflows) {
        expect(workflow, contains('Android ARM v7 APK (armeabi-v7a)'));
        expect(workflow, contains('Android ARM v8/v9 APK (arm64-v8a)'));
        expect(
          workflow,
          anyOf(
            contains('-android-armeabi-v7a.apk'),
            contains('Rain-Demo-Android-ARM-v7a-Build.apk'),
          ),
        );
        expect(
          workflow,
          anyOf(
            contains('-android-arm64-v8a.apk'),
            contains('Rain-Demo-Android-ARM-v8-v9-Build.apk'),
          ),
        );
        expect(workflow, isNot(contains('Android x86_64 APK')));
        expect(workflow, isNot(contains('Rain-Demo-Android-ARM-v7-Build.apk')));
        expect(workflow, isNot(contains('-android-x86_64.apk')));
        expect(workflow, isNot(contains('Rain-Demo-Android-x86_64-Build.apk')));
      }
    },
  );

  test('CI debug APK build targets Android ARMv7 and ARM64 only', () {
    final workflow = _repoFile('.github/workflows/ci.yml');

    expect(
      workflow,
      contains(
        'flutter build apk --debug --split-per-abi --target-platform android-arm,android-arm64',
      ),
    );
    expect(workflow, contains('Verify debug APK ABI split'));
    expect(workflow, contains('app-armeabi-v7a-debug.apk'));
    expect(workflow, contains('app-arm64-v8a-debug.apk'));
    expect(workflow, contains("grep -q 'lib/armeabi-v7a/'"));
    expect(
      workflow,
      contains("grep -q 'lib/armeabi-v7a/libjingle_peerconnection_so.so'"),
    );
    expect(workflow, contains("grep -q 'lib/arm64-v8a/'"));
    expect(
      workflow,
      contains("grep -q 'lib/arm64-v8a/libjingle_peerconnection_so.so'"),
    );
    expect(workflow, contains("if grep -q 'lib/x86_64/'"));
    expect(workflow, contains('rain-debug-armeabi-v7a-apk'));
    expect(workflow, contains('rain-debug-arm64-apk'));
    expect(workflow, isNot(contains('name: rain-debug-apk')));
  });

  test(
    'build artifacts workflow uploads ARM v7 and ARM v8/v9 APKs without archives',
    () {
      final workflow = _repoFile('.github/workflows/build-artifacts.yml');
      final androidBuildStep = RegExp(
        r'- name: Build Android APK artifacts(?<step>[\s\S]*?)\n\s*- name:',
      ).firstMatch(workflow)?.namedGroup('step');

      expect(androidBuildStep, isNotNull);
      expect(androidBuildStep, contains("'-AndroidArtifactSet'"));
      expect(androidBuildStep, contains("'mobile'"));
      expect(workflow, contains('Rain-Demo-Android-ARM-v7a-Build.apk'));
      expect(workflow, contains('Rain-Demo-Android-ARM-v8-v9-Build.apk'));
      expect(workflow, contains('Rain-release-android-armeabi-v7a.apk'));
      expect(workflow, contains('Rain-release-android-arm64-v8a.apk'));
      expect(
        workflow,
        contains('lib/armeabi-v7a/libjingle_peerconnection_so.so'),
      );
      expect(
        workflow,
        contains('lib/arm64-v8a/libjingle_peerconnection_so.so'),
      );
      expect(
        workflow,
        isNot(contains('Rain-Demo-Android-Universal-Build.apk')),
      );
      expect(workflow, isNot(contains('Rain-Demo-Android-x86_64-Build.apk')));
      expect(workflow, isNot(contains('Rain-release-android-universal.apk')));
      expect(workflow, isNot(contains('Rain-release-android-x86_64.apk')));
      expect(workflow, isNot(contains('.rar')));
      expect(workflow, isNot(contains('.zip')));
    },
  );

  test('CI docs describe current Android artifact set only', () {
    final docs = _repoFile('docs/github-ci-cd.md');

    expect(docs, contains('Rain-release-android-armeabi-v7a.apk'));
    expect(docs, contains('Rain-release-android-arm64-v8a.apk'));
    expect(docs, contains('Rain-Demo-Android-ARM-v7a-Build.apk'));
    expect(docs, contains('Rain-Demo-Android-ARM-v8-v9-Build.apk'));
    expect(docs, contains('docs/qa/voice-call-manual-device-gate.md'));
    expect(docs, isNot(contains('Android universal APK')));
    expect(docs, isNot(contains('Android `x86_64` APK')));
  });

  test('CI demo artifacts upload one portable Windows archive', () {
    final workflow = _repoFile('.github/workflows/ci.yml');

    expect(workflow, contains('path: artifacts/Rain-Demo-Windows-x64-Build'));
    expect(workflow, contains('Windows Flutter runtime DLL'));
    expect(workflow, contains('Windows WebRTC plugin DLL'));
    expect(workflow, contains('Windows WebRTC runtime DLL'));
    expect(workflow, contains('Windows SQLite runtime DLL'));
    expect(workflow, contains('lib/armeabi-v7a/libsqlite3.so'));
    expect(
      workflow,
      contains('lib/armeabi-v7a/libjingle_peerconnection_so.so'),
    );
    expect(workflow, contains('lib/arm64-v8a/libsqlite3.so'));
    expect(workflow, contains('lib/arm64-v8a/libjingle_peerconnection_so.so'));
    expect(
      workflow,
      contains(
        'Windows portable upload folder must not contain nested archives',
      ),
    );
    expect(
      workflow,
      isNot(contains('path: artifacts/Rain-Demo-Windows-x64-Build.zip')),
    );
    expect(workflow, contains('Rain-Demo-Android-ARM-v7a-Build.apk'));
    expect(workflow, contains('Rain-Demo-Android-ARM-v8-v9-Build.apk'));
    expect(workflow, isNot(contains('Rain-Demo-Android-x86_64-Build.apk')));
    expect(workflow, isNot(contains('lib/x86_64/libsqlite3.so')));
  });

  test('release workflow verifies native voice runtimes before upload', () {
    final workflow = _repoFile('.github/workflows/release.yml');

    expect(workflow, contains('Verify Windows release package'));
    expect(workflow, contains('flutter_webrtc_plugin.dll'));
    expect(workflow, contains('libwebrtc.dll'));
    expect(workflow, contains('Assert-ApkEntry'));
    expect(workflow, contains('lib/armeabi-v7a/libsqlite3.so'));
    expect(
      workflow,
      contains('lib/armeabi-v7a/libjingle_peerconnection_so.so'),
    );
    expect(workflow, contains('lib/arm64-v8a/libsqlite3.so'));
    expect(workflow, contains('lib/arm64-v8a/libjingle_peerconnection_so.so'));
  });

  test('manual voice gate requires real Android and Windows evidence', () {
    final gate = _repoFile('docs/qa/voice-call-manual-device-gate.md');
    final blockedRecord = _repoFile(
      'docs/qa/voice-call-manual-device-gate-2026-05-23.md',
    );

    expect(gate, contains('physical Android device'));
    expect(gate, contains('Windows machine'));
    expect(gate, contains('Git commit:'));
    expect(gate, contains('Android artifact SHA256:'));
    expect(gate, contains('Windows artifact SHA256:'));
    expect(gate, contains('Rain-Demo-Android-ARM-v8-v9-Build.apk'));
    expect(gate, contains('Rain-Demo-Windows-x64-Build'));
    expect(gate, contains('adb install -r'));
    expect(gate, contains('Windows -> Android direct route'));
    expect(gate, contains('Android -> Windows TURN relay'));
    expect(gate, contains('Android mic permission denied'));
    expect(gate, contains('Five repeated calls without app restart'));
    expect(gate, contains('File send blocked during active call'));
    expect(gate, contains('RTCRtpTransceiver has been disposed'));
    expect(gate, contains('No stale `Peer is busy` state'));
    expect(blockedRecord, contains('Gate status: BLOCKED'));
    expect(blockedRecord, contains('adb is not recognized on PATH'));
  });

  test('Rain core uses bundled SQLite native library packaging', () {
    final pubspec = _repoFile('packages/rain_core/pubspec.yaml');

    expect(pubspec, contains('drift_flutter: ^0.3.0'));
    expect(pubspec, contains('sqlite3: ^3.3.1'));
    expect(pubspec, isNot(contains('sqlite3_flutter_libs:')));
  });
}
