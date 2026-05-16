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
        'Release builds require at least one project-owned TURN/TURNS URL in RAIN_ICE_SERVERS.',
      ),
    );
    expect(
      script,
      contains('Release TURN servers must include username and credential.'),
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

  test('release script packages universal and per-ABI Android APKs', () {
    final script = _repoFile('scripts/build_release.ps1');

    expect(script, contains('--split-per-abi'));
    expect(script, contains('Rain-release'));
    expect(script, contains('Rain-openrelay-demo'));
    expect(script, contains('ARMv8/ARMv9 devices'));
    expect(script, contains('\$androidArtifactPrefix-android-universal.apk'));
    expect(script, contains('\$androidArtifactPrefix-android-arm64-v8a.apk'));
    expect(script, contains('\$androidArtifactPrefix-android-armeabi-v7a.apk'));
    expect(script, contains('\$androidArtifactPrefix-android-x86_64.apk'));
  });

  test('artifact workflows verify every Android APK architecture', () {
    final workflows = <String>[
      _repoFile('.github/workflows/ci.yml'),
      _repoFile('.github/workflows/build-artifacts.yml'),
      _repoFile('.github/workflows/release.yml'),
    ];

    for (final workflow in workflows) {
      expect(workflow, contains('Android ARM v7 APK (armeabi-v7a)'));
      expect(workflow, contains('Android ARM v8/v9 APK (arm64-v8a)'));
      expect(workflow, contains('Android x86_64 APK'));
      expect(workflow, contains('-android-armeabi-v7a.apk'));
      expect(workflow, contains('-android-arm64-v8a.apk'));
      expect(workflow, contains('-android-x86_64.apk'));
    }
  });
}
