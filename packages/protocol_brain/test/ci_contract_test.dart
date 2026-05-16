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
}
