import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _repoFile(String relativePath) {
  final workspaceRoot = Directory.current.parent.parent;
  return File.fromUri(
    workspaceRoot.uri.resolve(relativePath),
  ).readAsStringSync().replaceAll('\r\n', '\n');
}

void main() {
  test('Melos 7 workspace config discovers the maintained Rain packages', () {
    final rootPubspec = _repoFile('pubspec.yaml');

    expect(rootPubspec, contains('workspace:'));
    expect(rootPubspec, contains('  - apps/rain'));
    expect(rootPubspec, contains('  - packages/peer_core'));
    expect(rootPubspec, contains('  - packages/protocol_brain'));
    expect(rootPubspec, contains('  - packages/rain_core'));
    expect(rootPubspec, isNot(contains('apps/mobile_flutter')));
    expect(rootPubspec, contains('melos:'));
    expect(
      rootPubspec,
      contains('analyze: dart run melos exec -- flutter analyze'),
    );
    expect(rootPubspec, contains('test: dart run melos exec -- flutter test'));
  });

  test('workspace members opt into pub workspace resolution', () {
    for (final relativePath in <String>[
      'apps/rain/pubspec.yaml',
      'packages/peer_core/pubspec.yaml',
      'packages/protocol_brain/pubspec.yaml',
      'packages/rain_core/pubspec.yaml',
    ]) {
      expect(
        _repoFile(relativePath),
        contains('resolution: workspace'),
        reason: '$relativePath must use the root workspace lockfile.',
      );
    }
  });

  test('local dart defines stay out of source control', () {
    final gitignore = _repoFile('.gitignore');
    expect(gitignore, contains('apps/rain/tool/dart_defines.local.json'));
  });

  test('obsolete non-app scaffolding stays out of the Rain workspace', () {
    final workspaceRoot = Directory.current.parent.parent;

    for (final relativePath in <String>[
      'apps/mobile_flutter',
      'plans',
      'skills',
      '.agents',
      'opencode.json',
      'skills-lock.json',
      'PR_DESCRIPTION.md',
      'melos_rain_workspace.iml',
      '.github/workflows/phase4-verification-gate.yml',
    ]) {
      final uri = workspaceRoot.uri.resolve(relativePath);
      final exists =
          File.fromUri(uri).existsSync() || Directory.fromUri(uri).existsSync();
      expect(
        exists,
        isFalse,
        reason: '$relativePath is not used by the Rain app workspace.',
      );
    }
  });

  test(
    'removed database backend is not part of the maintained app surface',
    () {
      final workspaceRoot = Directory.current.parent.parent;
      final removedBackendToken =
          'supa'
          'base';
      final checkedRoots = <String>[
        'apps/rain/lib',
        'apps/rain/test',
        'apps/rain/tool',
        'packages/protocol_brain/lib',
        'packages/protocol_brain/test',
        'backend',
      ];
      final offenders = <String>[];

      for (final relativeRoot in checkedRoots) {
        final directory = Directory.fromUri(
          workspaceRoot.uri.resolve(relativeRoot),
        );
        if (!directory.existsSync()) {
          continue;
        }
        for (final file
            in directory.listSync(recursive: true).whereType<File>()) {
          final path = file.path.replaceAll('\\', '/');
          if (path.contains('/node_modules/')) {
            continue;
          }
          final contents = file.readAsStringSync().toLowerCase();
          if (path.toLowerCase().contains(removedBackendToken) ||
              contents.contains(removedBackendToken)) {
            offenders.add(file.path);
          }
        }
      }

      expect(offenders, isEmpty);
    },
  );
}
