import 'package:shared_preferences/shared_preferences.dart';

enum CallAudioOutputPreference { systemDefault, speaker, bluetooth }

final class AppAudioSettings {
  const AppAudioSettings({
    this.soundEffectsEnabled = true,
    this.soundEffectsVolume = 1.0,
    this.callSoundsEnabled = true,
    this.reduceSoundsDuringCall = true,
    this.defaultOutputPreference = CallAudioOutputPreference.systemDefault,
  });

  final bool soundEffectsEnabled;
  final double soundEffectsVolume;
  final bool callSoundsEnabled;
  final bool reduceSoundsDuringCall;
  final CallAudioOutputPreference defaultOutputPreference;

  AppAudioSettings copyWith({
    bool? soundEffectsEnabled,
    double? soundEffectsVolume,
    bool? callSoundsEnabled,
    bool? reduceSoundsDuringCall,
    CallAudioOutputPreference? defaultOutputPreference,
  }) {
    return AppAudioSettings(
      soundEffectsEnabled: soundEffectsEnabled ?? this.soundEffectsEnabled,
      soundEffectsVolume: soundEffectsVolume == null
          ? this.soundEffectsVolume
          : AppSettingsStore.normalizeSoundEffectsVolume(soundEffectsVolume),
      callSoundsEnabled: callSoundsEnabled ?? this.callSoundsEnabled,
      reduceSoundsDuringCall:
          reduceSoundsDuringCall ?? this.reduceSoundsDuringCall,
      defaultOutputPreference:
          defaultOutputPreference ?? this.defaultOutputPreference,
    );
  }
}

class AppSettingsStore {
  AppSettingsStore({SharedPreferencesAsync? preferences})
    : _preferences = preferences ?? SharedPreferencesAsync();

  static const bool defaultBackgroundServiceEnabled = false;
  static const bool defaultSoundEffectsEnabled = true;
  static const double defaultSoundEffectsVolume = 1.0;
  static const bool defaultCallSoundsEnabled = true;
  static const bool defaultReduceSoundsDuringCall = true;
  static const CallAudioOutputPreference defaultCallAudioOutputPreference =
      CallAudioOutputPreference.systemDefault;

  static const String _backgroundServiceEnabledKey =
      'background_service_enabled';
  static const String _selectedMicrophoneDeviceIdKey =
      'selected_microphone_device_id';
  static const String _selectedVideoInputDeviceIdKey =
      'selected_video_input_device_id';
  static const String _soundEffectsEnabledKey = 'sound_effects_enabled';
  static const String _soundEffectsVolumeKey = 'sound_effects_volume';
  static const String _callSoundsEnabledKey = 'call_sounds_enabled';
  static const String _reduceSoundsDuringCallKey = 'reduce_sounds_during_call';
  static const String _defaultCallAudioOutputPreferenceKey =
      'default_call_audio_output_preference';

  final SharedPreferencesAsync _preferences;

  static double normalizeSoundEffectsVolume(double volume) {
    if (!volume.isFinite) {
      return defaultSoundEffectsVolume;
    }
    return volume.clamp(0.0, 1.0).toDouble();
  }

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

  Future<String?> loadSelectedVideoInputDeviceId() async {
    final value = await _preferences.getString(_selectedVideoInputDeviceIdKey);
    final normalized = value?.trim();
    if (normalized == null || normalized.isEmpty) {
      return null;
    }
    return normalized;
  }

  Future<void> setSelectedVideoInputDeviceId(String? deviceId) async {
    final normalized = deviceId?.trim();
    if (normalized == null || normalized.isEmpty) {
      await _preferences.remove(_selectedVideoInputDeviceIdKey);
      return;
    }
    await _preferences.setString(_selectedVideoInputDeviceIdKey, normalized);
  }

  Future<AppAudioSettings> loadAudioSettings() async {
    return AppAudioSettings(
      soundEffectsEnabled: await loadSoundEffectsEnabled(),
      soundEffectsVolume: await loadSoundEffectsVolume(),
      callSoundsEnabled: await loadCallSoundsEnabled(),
      reduceSoundsDuringCall: await loadReduceSoundsDuringCall(),
      defaultOutputPreference: await loadDefaultCallAudioOutputPreference(),
    );
  }

  Future<bool> loadSoundEffectsEnabled() async {
    return await _preferences.getBool(_soundEffectsEnabledKey) ??
        defaultSoundEffectsEnabled;
  }

  Future<void> setSoundEffectsEnabled(bool enabled) async {
    await _preferences.setBool(_soundEffectsEnabledKey, enabled);
  }

  Future<double> loadSoundEffectsVolume() async {
    final value = await _preferences.getDouble(_soundEffectsVolumeKey);
    if (value == null) {
      return defaultSoundEffectsVolume;
    }
    return normalizeSoundEffectsVolume(value);
  }

  Future<void> setSoundEffectsVolume(double volume) async {
    await _preferences.setDouble(
      _soundEffectsVolumeKey,
      normalizeSoundEffectsVolume(volume),
    );
  }

  Future<bool> loadCallSoundsEnabled() async {
    return await _preferences.getBool(_callSoundsEnabledKey) ??
        defaultCallSoundsEnabled;
  }

  Future<void> setCallSoundsEnabled(bool enabled) async {
    await _preferences.setBool(_callSoundsEnabledKey, enabled);
  }

  Future<bool> loadReduceSoundsDuringCall() async {
    return await _preferences.getBool(_reduceSoundsDuringCallKey) ??
        defaultReduceSoundsDuringCall;
  }

  Future<void> setReduceSoundsDuringCall(bool enabled) async {
    await _preferences.setBool(_reduceSoundsDuringCallKey, enabled);
  }

  Future<CallAudioOutputPreference>
  loadDefaultCallAudioOutputPreference() async {
    final raw = await _preferences.getString(
      _defaultCallAudioOutputPreferenceKey,
    );
    if (raw == null) {
      return defaultCallAudioOutputPreference;
    }
    for (final value in CallAudioOutputPreference.values) {
      if (value.name == raw) {
        return value;
      }
    }
    return defaultCallAudioOutputPreference;
  }

  Future<void> setDefaultCallAudioOutputPreference(
    CallAudioOutputPreference preference,
  ) async {
    await _preferences.setString(
      _defaultCallAudioOutputPreferenceKey,
      preference.name,
    );
  }
}
