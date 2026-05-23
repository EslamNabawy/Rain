import 'package:shared_preferences/shared_preferences.dart';

class AppSettingsStore {
  AppSettingsStore({SharedPreferencesAsync? preferences})
    : _preferences = preferences ?? SharedPreferencesAsync();

  static const bool defaultBackgroundServiceEnabled = false;

  static const String _backgroundServiceEnabledKey =
      'background_service_enabled';
  static const String _selectedMicrophoneDeviceIdKey =
      'selected_microphone_device_id';

  final SharedPreferencesAsync _preferences;

  Future<bool> loadBackgroundServiceEnabled() async {
    // Background presence used a second isolate that could open the local
    // SQLite database while the foreground runtime was committing. Keep the
    // stored key for migration compatibility, but force direct in-app mode.
    await _preferences.setBool(_backgroundServiceEnabledKey, false);
    return false;
  }

  Future<void> setBackgroundServiceEnabled(bool enabled) async {
    await _preferences.setBool(_backgroundServiceEnabledKey, false);
  }

  Future<String?> loadSelectedMicrophoneDeviceId() async {
    final value = await _preferences.getString(_selectedMicrophoneDeviceIdKey);
    final normalized = value?.trim();
    if (normalized == null || normalized.isEmpty) {
      return null;
    }
    return normalized;
  }

  Future<void> setSelectedMicrophoneDeviceId(String? deviceId) async {
    final normalized = deviceId?.trim();
    if (normalized == null || normalized.isEmpty) {
      await _preferences.remove(_selectedMicrophoneDeviceIdKey);
      return;
    }
    await _preferences.setString(_selectedMicrophoneDeviceIdKey, normalized);
  }
}
