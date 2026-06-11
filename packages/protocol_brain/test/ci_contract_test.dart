/// # ci_contract_test.dart — protocol_brain package
///
/// Contract tests ensuring CI workflows use direct Flutter commands, avoid deprecated action runtimes, and enforce correct action versions.
///
/// **Key types:** (no top-level types — test-only file)
///
/// **Package:** protocol_brain
///
/// **Depends on:** flutter_test, dart:io
///
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _repoFile(String relativePath) {
  final workspaceRoot = Directory.current.parent.parent;
  return File.fromUri(
    workspaceRoot.uri.resolve(relativePath),
  ).readAsStringSync().replaceAll('\r\n', '\n');
}

void main() {
  test('CI workflow uses direct Flutter analyze and test commands', () {
    final workflow = _repoFile('.github/workflows/ci.yml');

    expect(workflow, contains('flutter analyze'));
    expect(workflow, contains('flutter test'));
    expect(workflow, isNot(contains('melos exec -- flutter analyze')));
    expect(workflow, isNot(contains('melos exec -- flutter test')));
  });

  test('GitHub workflows avoid deprecated JavaScript action runtimes', () {
    final workflows = <String>[
      _repoFile('.github/workflows/ci.yml'),
      _repoFile('.github/workflows/build-artifacts.yml'),
      _repoFile('.github/workflows/release.yml'),
    ];

    for (final workflow in workflows) {
      expect(workflow, isNot(contains('actions/setup-node@v4')));
      expect(workflow, isNot(contains('actions/setup-java@v4')));
      expect(workflow, isNot(contains('actions/upload-artifact@v4')));
    }

    final ciWorkflow = _repoFile('.github/workflows/ci.yml');
    final buildArtifactsWorkflow = _repoFile(
      '.github/workflows/build-artifacts.yml',
    );
    final releaseWorkflow = _repoFile('.github/workflows/release.yml');
    expect(ciWorkflow, contains('actions/setup-node@v6'));
    expect(ciWorkflow, contains('actions/setup-java@v5'));
    expect(ciWorkflow, contains('actions/setup-go@v6'));
    expect(ciWorkflow, contains('actions/upload-artifact@v7'));
    expect(ciWorkflow, contains('runs-on: windows-2022'));
    expect(ciWorkflow, contains("JAVA_VERSION: '21'"));
    expect(buildArtifactsWorkflow, contains("java-version: '21'"));
    expect(releaseWorkflow, contains("java-version: '21'"));
  });

  test('CI runs workflow lint before required checks pass', () {
    final workflow = _repoFile('.github/workflows/ci.yml');

    expect(workflow, contains('workflow-lint:'));
    expect(workflow, contains('github.com/rhysd/actionlint/cmd/actionlint'));
    expect(workflow, contains('bin/actionlint" -color'));
    expect(workflow, contains('needs.workflow-lint.result'));
  });

  test('CI runs Firebase emulator integration tests without skips', () {
    final workflow = _repoFile('.github/workflows/ci.yml');
    final script = _repoFile('scripts/ci_run_firebase_emulators.sh');

    expect(workflow, contains('firebase-emulator-tests:'));
    expect(workflow, contains('bash scripts/ci_run_firebase_emulators.sh'));
    expect(workflow, contains('needs.firebase-emulator-tests.result'));
    expect(script, contains('--only auth,database'));
    expect(script, contains('FIREBASE_TOOLS_VERSION'));
    expect(script, contains(r'firebase-tools@$FIREBASE_TOOLS_VERSION'));
    expect(script, contains('--dart-define=RUN_RAIN_INTEGRATION_TESTS=true'));
    expect(script, contains('integration_two_users_end2end_test.dart'));
    expect(
      script,
      contains('integration_two_devices_handshake_full_test.dart'),
    );
    expect(script, contains('integration_voice_signaling_emulator_test.dart'));
    expect(script, contains('integration_account_deletion_emulator_test.dart'));
  });

  test('hard release gates name auth lifecycle scenario tests', () {
    final buildArtifactsWorkflow = _repoFile(
      '.github/workflows/build-artifacts.yml',
    );
    final validatedReleaseWorkflow = _repoFile(
      '.github/workflows/validated-release.yml',
    );

    for (final workflow in <String>[
      buildArtifactsWorkflow,
      validatedReleaseWorkflow,
    ]) {
      expect(workflow, contains('Run auth lifecycle scenario tests'));
      expect(workflow, contains('SCN-AUTH-001'));
      expect(workflow, contains('SCN-AUTH-002'));
      expect(workflow, contains('SCN-AUTH-003'));
      expect(workflow, contains('SCN-AUTH-004'));
      expect(workflow, contains('auth_identity_source_of_truth_test.dart'));
      expect(workflow, contains('runtime_startup_test.dart'));
      expect(workflow, contains('settings_screen_test.dart'));
      expect(workflow, contains('app_routes_test.dart'));
    }
  });

  test('hard release gates validate the Obsidian vault', () {
    final buildArtifactsWorkflow = _repoFile(
      '.github/workflows/build-artifacts.yml',
    );
    final validatedReleaseWorkflow = _repoFile(
      '.github/workflows/validated-release.yml',
    );

    for (final workflow in <String>[
      buildArtifactsWorkflow,
      validatedReleaseWorkflow,
    ]) {
      expect(workflow, contains('Validate Obsidian vault'));
      expect(workflow, contains('./scripts/check_obsidian_vault.ps1'));
    }
  });

  test('Firebase backend CI audits moderate and higher dependency issues', () {
    final workflow = _repoFile('.github/workflows/ci.yml');
    final packageJson = _repoFile('backend/firebase/functions/package.json');
    final firebaseJson = _repoFile('backend/firebase/firebase.json');

    expect(workflow, contains('Audit Firebase functions dependencies'));
    expect(workflow, contains('npm run audit:moderate'));
    expect(
      packageJson,
      contains('npm audit --omit=dev --audit-level=moderate'),
    );
    expect(packageJson, contains('"node": ">=20 <25"'));
    expect(firebaseJson, contains('"runtime": "nodejs20"'));
  });
}
