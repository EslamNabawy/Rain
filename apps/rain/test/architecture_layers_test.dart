import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('app source stays in clean architecture layers', () {
    final lib = Directory('lib');
    expect(lib.existsSync(), isTrue);

    final forbiddenRootEntries = <String>[
      'bootstrap',
      'config',
      'firebase_options.dart',
      'navigation',
      'providers',
      'screens',
      'services',
      'theme',
      'widgets',
    ];

    for (final entry in forbiddenRootEntries) {
      expect(
        File('${lib.path}/$entry').existsSync() ||
            Directory('${lib.path}/$entry').existsSync(),
        isFalse,
        reason:
            'Use application/core/infrastructure/presentation, not lib/$entry.',
      );
    }

    for (final layer in <String>[
      'application',
      'core',
      'infrastructure',
      'presentation',
    ]) {
      expect(
        Directory('${lib.path}/$layer').existsSync(),
        isTrue,
        reason: 'Missing lib/$layer clean architecture layer.',
      );
    }
  });

  test('inner layers do not import presentation', () {
    final files = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));

    for (final file in files) {
      final normalizedPath = file.path.replaceAll('\\', '/');
      final contents = file.readAsStringSync();
      final importsPresentation = contents.contains(
        'package:rain/presentation/',
      );

      if (normalizedPath.startsWith('lib/core/') ||
          normalizedPath.startsWith('lib/application/') ||
          normalizedPath.startsWith('lib/infrastructure/')) {
        expect(
          importsPresentation,
          isFalse,
          reason: '${file.path} must not depend on presentation code.',
        );
      }
    }
  });

  test('old flat app package imports are not used', () {
    final oldImportPattern = RegExp(
      r'''package:rain/(bootstrap|config|firebase_options|navigation|providers|screens|services|theme|widgets)(/|\.dart|')''',
    );
    final files = <File>[
      ...Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart')),
      ...Directory('test')
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart')),
      ...Directory('tool')
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart')),
    ];

    for (final file in files) {
      expect(
        oldImportPattern.hasMatch(file.readAsStringSync()),
        isFalse,
        reason: '${file.path} still imports from the old flat app layout.',
      );
    }
  });
}
