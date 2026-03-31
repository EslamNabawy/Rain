import 'package:flutter_webrtc/flutter_webrtc.dart' as webrtc;

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
  Future<webrtc.RTCPeerConnection> createPeerConnection(Map<String, dynamic> config);
  Future<webrtc.RTCDataChannel> createDataChannel(
    webrtc.RTCPeerConnection pc,
    String label,
    webrtc.RTCDataChannelInit opts,
  );
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
  Future<webrtc.RTCPeerConnection> createPeerConnection(Map<String, dynamic> config) {
    return webrtc.createPeerConnection(config);
  }

  @override
  StorageBackend getLocalStorage() {
    return _storageBackend;
  }
}
