import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _repoFile(String relativePath) {
  final workspaceRoot = Directory.current.parent.parent;
  return File.fromUri(
    workspaceRoot.uri.resolve(relativePath),
  ).readAsStringSync().replaceAll('\r\n', '\n');
}

void main() {
  test('release script requires project-owned TURN release defines', () {
    final script = _repoFile('scripts/build_release.ps1');

    expect(script, contains('[string]\$DartDefinesFile'));
    expect(script, contains('[switch]\$AllowPublicTurnForDemo'));
    expect(script, contains('[switch]\$RelayTest'));
    expect(script, contains('[switch]\$ForceRelayOnlySmoke'));
    expect(script, contains('[string]\$TurnBrokerUrl'));
    expect(script, contains('[string]\$TurnProviderName'));
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
    expect(script, contains('Relay test builds require RAIN_TURN_BROKER_URL.'));
    expect(
      script,
      contains(
        'Relay test builds require -TurnBrokerUrl when -ForceRelayOnlySmoke is set.',
      ),
    );
    expect(script, contains('RAIN_ICE_STRATEGY'));
    expect(script, contains('RAIN_TURN_PROVIDER_ORDER'));
    expect(script, contains('rain-relay-test-defines.generated.json'));
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
      contains('Demo Android signing is enabled for non-production artifacts.'),
    );
    expect(script, contains('Resolve-KeytoolPath'));
    expect(script, contains('JAVA_HOME'));
    expect(script, contains('\$name is required for release signing.'));
    expect(script, contains('RAIN_RELEASE_STORE_FILE does not exist:'));
    expect(script, contains('\$LASTEXITCODE -ne 0'));
  });

  test('Android release signing is required and never debug-signed', () {
    final gradle = _repoFile('apps/rain/android/app/build.gradle.kts');

    expect(gradle, contains('RAIN_RELEASE_STORE_FILE'));
    expect(gradle, contains('RAIN_RELEASE_STORE_PASSWORD'));
    expect(gradle, contains('RAIN_RELEASE_KEY_ALIAS'));
    expect(gradle, contains('RAIN_RELEASE_KEY_PASSWORD'));
    expect(gradle, contains('signingConfigs.getByName("release")'));
    expect(gradle, contains('isReleaseBuild'));
    expect(gradle, isNot(contains('signingConfigs.getByName("debug")')));
    expect(gradle, isNot(contains('Signing with the debug keys')));
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

  test('relay test dart defines use broker and STUN-only base ICE', () {
    final defines = _repoFile(
      'apps/rain/tool/dart_defines.relay-test.example.json',
    );

    expect(defines, contains('/rainTurnCredentials'));
    expect(defines, contains('"RAIN_ALLOW_PUBLIC_TURN": "false"'));
    expect(defines, contains('stun:stun.l.google.com:19302'));
    expect(defines, contains('stun:stun.cloudflare.com:3478'));
    expect(defines, isNot(contains('openrelay.metered.ca')));
    expect(defines, isNot(contains('turn:')));
    expect(defines, isNot(contains('turns:')));
  });

  test('Firebase functions do not embed managed TURN provider secrets', () {
    final functions = _repoFile('backend/firebase/functions/index.js');

    expect(functions, isNot(contains('TWILIO')));
    expect(functions, isNot(contains('CLOUDFLARE')));
    expect(functions, isNot(contains('rainTurnCredentials')));
    expect(functions, isNot(contains('generate-ice-servers')));
    expect(functions, contains('cleanupPresence'));
    expect(functions, contains('cleanupRooms'));
  });

  test('release script defaults to mobile APKs with optional all-ABI builds', () {
    final script = _repoFile('scripts/build_release.ps1');

    expect(script, contains('--split-per-abi'));
    expect(script, contains('Assert-AndroidApkContainsSqlite'));
    expect(script, contains('lib/\$abi/libsqlite3.so'));
    expect(script, contains('Rain-release'));
    expect(script, contains('Rain-Demo'));
    expect(script, contains('Rain-Relay-Test'));
    expect(script, contains('ARMv8/ARMv9 devices'));
    expect(script, contains('Rain-Demo-Android-Universal-Build.apk'));
    expect(script, contains('Rain-Demo-Android-ARM-v8-v9-Build.apk'));
    expect(script, contains('Rain-Demo-Android-ARM-v7-Build.apk'));
    expect(script, contains('Rain-Demo-Android-x86_64-Build.apk'));
    expect(script, contains('Rain-Demo-Windows-x64-Build'));
    expect(script, contains('[string]\$AndroidArtifactSet = \'mobile\''));
    expect(script, contains('[switch]\$GenerateSizeReports'));
    expect(
      script,
      contains(
        'Skipping Android universal/x86_64 release APK; mobile user artifacts are ARM-only',
      ),
    );
    expect(script, contains('android-arm,android-arm64'));
    expect(script, contains('\$androidArtifactPrefix-android-universal.apk'));
    expect(script, contains('\$androidArtifactPrefix-android-arm64-v8a.apk'));
    expect(script, contains('\$androidArtifactPrefix-android-armeabi-v7a.apk'));
    expect(script, contains('\$androidArtifactPrefix-android-x86_64.apk'));
  });

  test('Windows release packaging includes Dart native assets', () {
    final script = _repoFile('scripts/build_release.ps1');

    expect(script, contains('Copy-WindowsNativeAssets'));
    expect(script, contains('Assert-WindowsNativeAssetsPackaged'));
    expect(script, contains('Assert-WindowsSqliteExports'));
    expect(script, contains('Resolve-DumpbinPath'));
    expect(script, contains('sqlite3_temp_directory'));
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

  test('CI and release workflows verify mobile Android APK architectures', () {
    final workflows = <String>[
      _repoFile('.github/workflows/ci.yml'),
      _repoFile('.github/workflows/release.yml'),
    ];

    for (final workflow in workflows) {
      expect(workflow, contains('Android ARM v7 APK (armeabi-v7a)'));
      expect(workflow, contains('Android ARM v8/v9 APK (arm64-v8a)'));
      expect(workflow, isNot(contains('Android x86_64 APK')));
      expect(workflow, isNot(contains('Android universal APK')));
      expect(
        workflow,
        anyOf(
          contains('-android-armeabi-v7a.apk'),
          contains('Rain-Demo-Android-ARM-v7-Build.apk'),
        ),
      );
      expect(
        workflow,
        anyOf(
          contains('-android-arm64-v8a.apk'),
          contains('Rain-Demo-Android-ARM-v8-v9-Build.apk'),
        ),
      );
    }
  });

  test('build artifacts workflow uploads mobile APKs without archives', () {
    final workflow = _repoFile('.github/workflows/build-artifacts.yml');
    final androidBuildStep = RegExp(
      r'- name: Build Android APK artifacts(?<step>[\s\S]*?)\n\s*- name:',
    ).firstMatch(workflow)?.namedGroup('step');

    expect(androidBuildStep, isNotNull);
    expect(androidBuildStep, contains("'-AndroidArtifactSet'"));
    expect(androidBuildStep, contains("'mobile'"));
    expect(androidBuildStep, contains("'-GenerateSizeReports'"));
    expect(
      workflow,
      contains(
        'Default mobile artifact build must not include oversized optional APK',
      ),
    );
    expect(workflow, contains('Rain-Demo-Android-Size-Reports'));
    expect(workflow, contains('Rain-Relay-Test-Android-Size-Reports'));
    expect(workflow, contains('Rain-Relay-Test-Android-Builds'));
    expect(workflow, contains('Rain-Demo-Android-ARM-v7-Build.apk'));
    expect(workflow, contains('Rain-Demo-Android-ARM-v8-v9-Build.apk'));
    expect(workflow, isNot(contains('.rar')));
    expect(workflow, isNot(contains('.zip')));
  });

  test('build artifacts workflow has explicit relay test profile', () {
    final workflow = _repoFile('.github/workflows/build-artifacts.yml');

    expect(workflow, contains('build_relay_test'));
    expect(workflow, contains('relay-test'));
    expect(workflow, contains('RAIN_TURN_BROKER_URL'));
    expect(workflow, contains('RAIN_SIGNALING_ENCRYPTION_KEY'));
    expect(workflow, contains('RAIN_ALLOW_PUBLIC_TURN=false'));
    expect(
      workflow,
      contains('Relay-test build requires RAIN_TURN_BROKER_URL.'),
    );
    expect(
      workflow,
      contains('Relay-test build requires RAIN_SIGNALING_ENCRYPTION_KEY.'),
    );
    expect(workflow, contains('Rain-Relay-Test-Android-Builds'));
    expect(workflow, contains('Rain-Relay-Test-Windows-x64-Build'));
  });

  test(
    'default demo artifacts do not pretend to be production relay artifacts',
    () {
      final workflow = _repoFile('.github/workflows/build-artifacts.yml');

      expect(workflow, contains('Rain-Demo-Android-ARM-v7-Build.apk'));
      expect(workflow, isNot(contains('Rain-Production-OpenRelay')));
      expect(workflow, isNot(contains('Rain-Release-OpenRelay')));
    },
  );

  test('CI demo artifacts use OpenRelay and portable output', () {
    final workflow = _repoFile('.github/workflows/ci.yml');

    expect(workflow, contains('Prepare OpenRelay demo dart defines'));
    expect(workflow, contains('-AllowPublicTurnForDemo'));
    expect(workflow, contains('artifacts/Rain-Demo-Windows-x64-Build'));
    expect(workflow, contains('Windows SQLite runtime DLL'));
    expect(workflow, contains('lib/armeabi-v7a/libsqlite3.so'));
    expect(workflow, contains('lib/arm64-v8a/libsqlite3.so'));
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
    expect(workflow, contains('Rain-Demo-Android-ARM-v7-Build.apk'));
    expect(workflow, contains('Rain-Demo-Android-ARM-v8-v9-Build.apk'));
    expect(workflow, contains('Rain-Demo-Android-Size-Reports'));
    expect(
      workflow,
      contains(
        'Default CI/CD mobile artifacts must not include oversized optional APK',
      ),
    );
  });

  test('Rain core uses bundled SQLite native library packaging', () {
    final pubspec = _repoFile('packages/rain_core/pubspec.yaml');

    expect(pubspec, contains('drift_flutter: ^0.3.0'));
    expect(pubspec, contains('sqlite3: ^3.3.1'));
    expect(pubspec, isNot(contains('sqlite3_flutter_libs:')));
  });
}
