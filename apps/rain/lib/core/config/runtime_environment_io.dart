import 'dart:convert';
import 'dart:io';

Map<String, String> currentProcessEnvironment() {
  final merged = <String, String>{};

  for (final file in _candidateConfigFiles()) {
    if (!file.existsSync()) {
      continue;
    }
    try {
      final decoded = jsonDecode(file.readAsStringSync());
      if (decoded is Map<String, dynamic>) {
        for (final entry in decoded.entries) {
          final value = entry.value?.toString().trim() ?? '';
          if (value.isNotEmpty) {
            merged[entry.key] = value;
          }
        }
      }
    } catch (_) {
      // Ignore malformed local config files and keep falling back to the
      // process environment.
    }
  }

  merged.addAll(Platform.environment);
  return merged;
}

Iterable<File> _candidateConfigFiles() sync* {
  final seen = <String>{};
  for (final baseDir in <Directory>[
    Directory.current,
    File(Platform.resolvedExecutable).parent,
  ]) {
    for (final dir in _ancestorDirectories(baseDir)) {
      for (final relativePath in <String>[
        'tool${Platform.pathSeparator}dart_defines.local.json',
        'apps${Platform.pathSeparator}rain${Platform.pathSeparator}tool${Platform.pathSeparator}dart_defines.local.json',
        'dart_defines.local.json',
      ]) {
        final path = '${dir.path}${Platform.pathSeparator}$relativePath';
        if (seen.add(path)) {
          yield File(path);
        }
      }
    }
  }
}

Iterable<Directory> _ancestorDirectories(Directory start) sync* {
  Directory? current = start.absolute;
  while (current != null) {
    yield current;
    final parent = current.parent;
    if (parent.path == current.path) {
      break;
    }
    current = parent;
  }
}
