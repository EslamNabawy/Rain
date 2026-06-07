/// Low-level WebRTC stats-report parsing utilities.
///
/// Provides case-insensitive key lookup and typed extraction from the
/// `Map<dynamic, dynamic>` values that [StatsReport]s expose.
library;

Object? statValue(Map<dynamic, dynamic> values, Iterable<String> keys) {
  for (final key in keys) {
    if (values.containsKey(key)) {
      return values[key];
    }
  }
  final normalized = <String, Object?>{
    for (final entry in values.entries)
      entry.key.toString().toLowerCase(): entry.value,
  };
  for (final key in keys) {
    final value = normalized[key.toLowerCase()];
    if (value != null) {
      return value;
    }
  }
  return null;
}

bool hasAnyStat(Map<dynamic, dynamic> values, Iterable<String> keys) {
  return statValue(values, keys) != null;
}

String? stringStat(Map<dynamic, dynamic> values, Iterable<String> keys) {
  final value = statValue(values, keys);
  if (value == null) {
    return null;
  }
  final text = value.toString().trim();
  return text.isEmpty ? null : text;
}

double? doubleStat(Map<dynamic, dynamic> values, Iterable<String> keys) {
  final value = statValue(values, keys);
  if (value is num) {
    return value.toDouble();
  }
  if (value is String) {
    return double.tryParse(value.trim());
  }
  return null;
}

bool? boolStat(Map<dynamic, dynamic> values, Iterable<String> keys) {
  final value = statValue(values, keys);
  if (value is bool) {
    return value;
  }
  if (value is String) {
    final normalized = value.trim().toLowerCase();
    if (normalized == 'true') {
      return true;
    }
    if (normalized == 'false') {
      return false;
    }
  }
  return null;
}
