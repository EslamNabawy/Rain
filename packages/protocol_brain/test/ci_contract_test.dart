import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _repoFile(String relativePath) {
  final workspaceRoot = Directory.current.parent.parent;
  return File.fromUri(
    workspaceRoot.uri.resolve(relativePath),
  ).readAsStringSync().replaceAll('\r\n', '\n');
}

void main() {
  test('Phase 4 runner executes real Flutter checks', () {
    final runner = _repoFile('scripts/phase4-runner.js');

    expect(runner, contains('spawnSync'));
    expect(runner, contains("['analyze']"));
    expect(runner, contains("['test']"));
    expect(runner, isNot(contains('Simulated checks')));
    expect(runner, isNot(contains("status: 'PASS'")));
  });

  test('Phase 4 workflow does not install nonexistent npm dependencies', () {
    final workflow = _repoFile(
      '.github/workflows/phase4-verification-gate.yml',
    );

    expect(workflow, contains('subosito/flutter-action'));
    expect(workflow, contains('node scripts/phase4-runner.js'));
    expect(workflow, isNot(contains('npm ci || npm install')));
    expect(workflow, isNot(contains('Gate Pass')));
  });

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
      _repoFile('.github/workflows/phase4-verification-gate.yml'),
    ];

    for (final workflow in workflows) {
      expect(workflow, isNot(contains('actions/setup-node@v4')));
      expect(workflow, isNot(contains('actions/setup-java@v4')));
      expect(workflow, isNot(contains('actions/upload-artifact@v4')));
    }

    final ciWorkflow = _repoFile('.github/workflows/ci.yml');
    expect(ciWorkflow, contains('actions/setup-node@v6'));
    expect(ciWorkflow, contains('actions/setup-java@v5'));
    expect(ciWorkflow, contains('actions/upload-artifact@v7'));
    expect(ciWorkflow, contains('runs-on: windows-2022'));
  });
}
