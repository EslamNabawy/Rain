import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('apps and rain_core do not import peer_core directly', () {
    final workspaceRoot = Directory.current.parent.parent;
    final appLib = Directory.fromUri(workspaceRoot.uri.resolve('apps/rain/lib/'));
    final rainCoreLib = Directory.fromUri(
      workspaceRoot.uri.resolve('packages/rain_core/lib/'),
    );

    final offenders = <String>[];
    for (final directory in <Directory>[appLib, rainCoreLib]) {
      for (final file in directory.listSync(recursive: true).whereType<File>()) {
        if (!file.path.endsWith('.dart')) {
          continue;
        }
        final contents = file.readAsStringSync();
        if (contents.contains("package:peer_core/")) {
          offenders.add(file.path);
        }
      }
    }

    expect(offenders, isEmpty, reason: 'Direct peer_core imports found: $offenders');
  });

  test('peer_core stays isolated from higher layers and backends', () {
    final peerCoreLib = Directory.fromUri(
      Directory.current.uri.resolve('../peer_core/lib/'),
    );

    final forbiddenImports = <String>[
      'package:protocol_brain/',
      'package:rain_core/',
      'package:firebase_',
      'package:supabase_flutter/',
    ];

    final offenders = <String>[];
    for (final file in peerCoreLib.listSync(recursive: true).whereType<File>()) {
      if (!file.path.endsWith('.dart')) {
        continue;
      }
      final contents = file.readAsStringSync();
      if (forbiddenImports.any(contents.contains)) {
        offenders.add(file.path);
      }
    }

    expect(offenders, isEmpty, reason: 'Forbidden peer_core imports found: $offenders');
  });

  test('protocol_brain backend imports stay inside adapters', () {
    final protocolBrainLib = Directory.fromUri(Directory.current.uri.resolve('lib/'));
    final offenders = <String>[];

    for (final file in protocolBrainLib.listSync(recursive: true).whereType<File>()) {
      if (!file.path.endsWith('.dart')) {
        continue;
      }

      final normalizedPath = file.uri.path;
      if (normalizedPath.contains('/adapters/')) {
        continue;
      }

      final contents = file.readAsStringSync();
      if (contents.contains('package:firebase_') ||
          contents.contains('package:supabase_flutter/')) {
        offenders.add(file.path);
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'Backend packages leaked outside adapters: $offenders',
    );
  });
}
