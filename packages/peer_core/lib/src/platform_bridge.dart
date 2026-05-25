import 'package:flutter_webrtc/flutter_webrtc.dart' as webrtc;

const String webRtcAudioInputDeviceKind = 'audioinput';
const String webRtcAudioOutputDeviceKind = 'audiooutput';
const String webRtcVideoInputDeviceKind = 'videoinput';

extension WebRtcMediaDeviceInfoX on webrtc.MediaDeviceInfo {
  String get normalizedKind => (kind ?? '').trim().toLowerCase();

  String get normalizedDeviceId => deviceId.trim();

  bool get hasUsableDeviceId => normalizedDeviceId.isNotEmpty;

  bool get isAudioInputDevice =>
      hasUsableDeviceId && normalizedKind == webRtcAudioInputDeviceKind;

  bool get isAudioOutputDevice =>
      hasUsableDeviceId && normalizedKind == webRtcAudioOutputDeviceKind;

  bool get isVideoInputDevice =>
      hasUsableDeviceId && normalizedKind == webRtcVideoInputDeviceKind;
}

abstract class StorageBackend {
  Future<void> write(String key, String value);
  Future<String?> read(String key);
  Future<void> delete(String key);
}

class MemoryStorageBackend implements StorageBackend {
  final Map<String, String> _values = <String, String>{};

  @override
  Future<void> delete(String key) async {
    _values.remove(key);
  }

  @override
  Future<String?> read(String key) async {
    return _values[key];
  }

  @override
  Future<void> write(String key, String value) async {
    _values[key] = value;
  }
}

abstract class PlatformBridge {
  Future<webrtc.RTCPeerConnection> createPeerConnection(
    Map<String, dynamic> config,
  );
  Future<webrtc.RTCDataChannel> createDataChannel(
    webrtc.RTCPeerConnection pc,
    String label,
    webrtc.RTCDataChannelInit opts,
  );
  Future<webrtc.MediaStream> getUserMedia(Map<String, dynamic> constraints);
  Future<List<webrtc.MediaDeviceInfo>> enumerateMediaDevices();
  Future<void> selectAudioInput(String deviceId);
  Future<void> selectAudioOutput(String deviceId);
  Future<void> setSpeakerphoneOn(bool enabled);
  Future<void> setSpeakerphoneOnButPreferBluetooth();
  Future<void> prepareVoiceAudio();
  Future<void> clearVoiceAudio();
  Future<void> setMicrophoneMuted(
    webrtc.MediaStreamTrack track, {
    required bool muted,
  });
  Future<void> switchCamera(webrtc.MediaStreamTrack track);
  StorageBackend getLocalStorage();
}

class FlutterWebRTCBridge implements PlatformBridge {
  FlutterWebRTCBridge({StorageBackend? storageBackend})
    : _storageBackend = storageBackend ?? MemoryStorageBackend();

  final StorageBackend _storageBackend;

  @override
  Future<webrtc.RTCDataChannel> createDataChannel(
    webrtc.RTCPeerConnection pc,
    String label,
    webrtc.RTCDataChannelInit opts,
  ) {
    return pc.createDataChannel(label, opts);
  }

  @override
  Future<webrtc.RTCPeerConnection> createPeerConnection(
    Map<String, dynamic> config,
  ) {
    return webrtc.createPeerConnection(config);
  }

  @override
  Future<void> clearVoiceAudio() async {
    if (webrtc.WebRTC.platformIsAndroid) {
      await webrtc.Helper.clearAndroidCommunicationDevice();
    }
  }

  @override
  Future<List<webrtc.MediaDeviceInfo>> enumerateMediaDevices() {
    return webrtc.navigator.mediaDevices.enumerateDevices();
  }

  @override
  Future<webrtc.MediaStream> getUserMedia(Map<String, dynamic> constraints) {
    return webrtc.navigator.mediaDevices.getUserMedia(constraints);
  }

  @override
  StorageBackend getLocalStorage() {
    return _storageBackend;
  }

  @override
  Future<void> prepareVoiceAudio() async {
    if (webrtc.WebRTC.platformIsAndroid) {
      await webrtc.Helper.setAndroidAudioConfiguration(
        webrtc.AndroidAudioConfiguration.communication,
      );
    }
  }

  @override
  Future<void> setMicrophoneMuted(
    webrtc.MediaStreamTrack track, {
    required bool muted,
  }) async {
    track.enabled = !muted;
    try {
      await webrtc.Helper.setMicrophoneMute(muted, track);
    } catch (_) {
      // Track.enabled is the portable fallback; native helper support varies.
    }
  }

  @override
  Future<void> switchCamera(webrtc.MediaStreamTrack track) {
    return webrtc.Helper.switchCamera(track);
  }

  @override
  Future<void> selectAudioInput(String deviceId) {
    return webrtc.Helper.selectAudioInput(deviceId);
  }

  @override
  Future<void> selectAudioOutput(String deviceId) {
    return webrtc.Helper.selectAudioOutput(deviceId);
  }

  @override
  Future<void> setSpeakerphoneOn(bool enabled) {
    return webrtc.Helper.setSpeakerphoneOn(enabled);
  }

  @override
  Future<void> setSpeakerphoneOnButPreferBluetooth() {
    return webrtc.Helper.setSpeakerphoneOnButPreferBluetooth();
  }
}
