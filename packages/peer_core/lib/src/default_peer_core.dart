import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:uuid/uuid.dart';

import 'models.dart';
import 'state_machine.dart';

const _maxMessageBytes = 16 * 1024;
const _chunkPayloadBytes = 12 * 1024;
const _maxChunkFrames = 1024;
const _maxPendingChunkBuffers = 64;
const _chunkBufferTtl = Duration(minutes: 2);

class DefaultPeerCore implements PeerCore {
  DefaultPeerCore({Uuid? uuid}) : _uuid = uuid ?? const Uuid();

  final Uuid _uuid;
  final PeerStateMachine _stateMachine = PeerStateMachine();
  final StreamController<RTCIceCandidate> _iceController =
      StreamController<RTCIceCandidate>.broadcast();
  final StreamController<void> _connectedController =
      StreamController<void>.broadcast();
  final StreamController<void> _disconnectedController =
      StreamController<void>.broadcast();
  final StreamController<PeerMessage> _messageController =
      StreamController<PeerMessage>.broadcast();
  final StreamController<String> _channelOpenController =
      StreamController<String>.broadcast();
  final StreamController<String> _channelCloseController =
      StreamController<String>.broadcast();
  final StreamController<PeerState> _stateController =
      StreamController<PeerState>.broadcast();

  final Map<String, RTCDataChannel> _channels = <String, RTCDataChannel>{};
  final Set<String> _openChannels = <String>{};
  final Map<String, _ChunkAccumulator> _chunkBuffers =
      <String, _ChunkAccumulator>{};
  final List<RTCIceCandidate> _localCandidates = <RTCIceCandidate>[];

  RTCPeerConnection? _peerConnection;
  PeerConfig? _config;
  bool _destroying = false;

  @override
  Stream<RTCIceCandidate> get onIceCandidate => _iceController.stream;

  @override
  Stream<void> get onConnected => _connectedController.stream;

  @override
  Stream<void> get onDisconnected => _disconnectedController.stream;

  @override
  Stream<PeerMessage> get onMessage => _messageController.stream;

  @override
  Stream<String> get onChannelOpen => _channelOpenController.stream;

  @override
  Stream<String> get onChannelClose => _channelCloseController.stream;

  @override
  Stream<PeerState> get onStateChange => _stateController.stream;

  @override
  PeerState get state => _stateMachine.state;

  @override
  Future<void> addIceCandidate(RTCIceCandidate candidate) async {
    await _requirePeerConnection().addCandidate(candidate);
  }

  @override
  Future<void> closeChannel(String channelId) async {
    final channel = _channels.remove(channelId);
    await channel?.close();
    _channelCloseController.add(channelId);
  }

  @override
  Future<RTCSessionDescription> createOffer() async {
    _ensureState(<PeerState>{PeerState.ready});
    await openChannel(PeerChannels.chat);
    await openChannel(PeerChannels.control);
    await openChannel(PeerChannels.file);
    final offer = await _requirePeerConnection().createOffer();
    await _requirePeerConnection().setLocalDescription(offer);
    _transition(PeerState.offering);
    return offer;
  }

  @override
  Future<void> destroy() async {
    _destroying = true;
    try {
      for (final channel in _channels.values.toList()) {
        await channel.close();
      }
    } finally {
      _destroying = false;
    }
    _channels.clear();
    _openChannels.clear();
    await _peerConnection?.close();
    _peerConnection = null;
    _localCandidates.clear();
    _chunkBuffers.clear();
    if (state != PeerState.idle) {
      _transition(PeerState.idle);
    }
  }

  @override
  List<RTCIceCandidate> getLocalCandidates() {
    return List<RTCIceCandidate>.unmodifiable(_localCandidates);
  }

  @override
  Future<void> init(PeerConfig config) async {
    if (_peerConnection != null) {
      await destroy();
    }

    _config = config;
    _peerConnection = await config.platform.createPeerConnection(
      config.toRtcConfiguration(),
    );
    _wirePeerConnection(_peerConnection!);
    _transition(PeerState.ready);
  }

  @override
  Future<void> openChannel(String channelId, {RTCDataChannelInit? opts}) async {
    if (_channels.containsKey(channelId)) {
      return;
    }

    final channel = await _config!.platform.createDataChannel(
      _requirePeerConnection(),
      channelId,
      opts ?? _config!.defaultChannelOptions(),
    );
    _attachChannel(channelId, channel);
  }

  @override
  Future<int> bufferedAmount(String channelId) async {
    final channel = _channels[channelId];
    if (channel == null) {
      throw StateError('Channel $channelId is not open.');
    }
    return channel.getBufferedAmount();
  }

  @override
  bool isChannelOpen(String channelId) {
    return _openChannels.contains(channelId);
  }

  @override
  Future<PeerConnectionRoute> currentRoute() async {
    final reports = await _requirePeerConnection().getStats();
    return PeerConnectionRoute.fromStats(
      reports,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
  }

  @override
  void send(String channelId, dynamic data) {
    final channel = _channels[channelId];
    if (channel == null) {
      throw StateError('Channel $channelId is not open.');
    }
    if (channel.state != RTCDataChannelState.RTCDataChannelOpen) {
      throw StateError('Channel $channelId is not ready.');
    }

    _sendChunkedIfNeeded(channel, data);
  }

  @override
  Future<void> setAnswer(RTCSessionDescription answer) async {
    _ensureState(<PeerState>{PeerState.offering});
    await _requirePeerConnection().setRemoteDescription(answer);
    _transition(PeerState.connecting);
  }

  @override
  Future<RTCSessionDescription> setOffer(RTCSessionDescription offer) async {
    _ensureState(<PeerState>{PeerState.ready});
    await _requirePeerConnection().setRemoteDescription(offer);
    _transition(PeerState.answering);
    final answer = await _requirePeerConnection().createAnswer();
    await _requirePeerConnection().setLocalDescription(answer);
    return answer;
  }

  void _attachChannel(String channelId, RTCDataChannel channel) {
    _channels[channelId] = channel;
    channel.onDataChannelState = (RTCDataChannelState state) {
      if (state == RTCDataChannelState.RTCDataChannelOpen) {
        _openChannels.add(channelId);
        _channelOpenController.add(channelId);
        _markConnectedIfDataChannelsReady();
      } else if (state == RTCDataChannelState.RTCDataChannelClosed) {
        _channels.remove(channelId);
        _openChannels.remove(channelId);
        _channelCloseController.add(channelId);
        if (!_destroying &&
            _isRequiredDataChannel(channelId) &&
            this.state == PeerState.connected) {
          _transition(PeerState.reconnecting);
          _disconnectedController.add(null);
        }
      }
    };
    if (channel.state == RTCDataChannelState.RTCDataChannelOpen) {
      _openChannels.add(channelId);
      _markConnectedIfDataChannelsReady();
    }
    channel.onMessage = (RTCDataChannelMessage message) {
      final payload = message.isBinary
          ? Uint8List.fromList(message.binary)
          : message.text;
      _emitIncomingMessage(channelId, payload);
    };
  }

  void _emitIncomingMessage(String channelId, Object payload) {
    if (payload is String) {
      final maybeChunk = _ChunkFrame.tryParse(payload);
      if (maybeChunk != null) {
        final now = DateTime.now();
        _pruneStaleChunkBuffers(now);
        final existing = _chunkBuffers[maybeChunk.id];
        if (existing != null && !existing.matches(maybeChunk)) {
          _chunkBuffers.remove(maybeChunk.id);
          return;
        }
        if (existing == null &&
            _chunkBuffers.length >= _maxPendingChunkBuffers) {
          return;
        }
        final accumulator =
            existing ??
            (_chunkBuffers[maybeChunk.id] = _ChunkAccumulator(
              maybeChunk.total,
              maybeChunk.isBinary,
              createdAt: now,
            ));
        accumulator.add(maybeChunk.index, maybeChunk.payload);
        if (accumulator.isComplete) {
          _chunkBuffers.remove(maybeChunk.id);
          final assembled = accumulator.join();
          final Object data;
          try {
            data = accumulator.isBinary
                ? assembled
                : utf8.decode(assembled, allowMalformed: false);
          } catch (_) {
            return;
          }
          _messageController.add(
            PeerMessage(
              channelId: channelId,
              data: data,
              receivedAt: DateTime.now(),
            ),
          );
        }
        return;
      }
      if (_ChunkFrame.hasChunkEnvelope(payload)) {
        return;
      }
    }

    _messageController.add(
      PeerMessage(
        channelId: channelId,
        data: payload,
        receivedAt: DateTime.now(),
      ),
    );
  }

  void _ensureState(Set<PeerState> allowed) {
    if (!allowed.contains(state)) {
      throw StateError('PeerCore is in $state, expected one of $allowed');
    }
  }

  RTCPeerConnection _requirePeerConnection() {
    final peerConnection = _peerConnection;
    if (peerConnection == null || _config == null) {
      throw StateError('PeerCore has not been initialized.');
    }
    return peerConnection;
  }

  void _sendChunkedIfNeeded(RTCDataChannel channel, dynamic data) {
    if (data is Uint8List) {
      if (data.lengthInBytes <= _maxMessageBytes) {
        channel.send(RTCDataChannelMessage.fromBinary(data));
        return;
      }
      _sendChunkFrames(channel, data, isBinary: true);
      return;
    }

    final text = data.toString();
    final bytes = Uint8List.fromList(utf8.encode(text));
    if (bytes.lengthInBytes <= _maxMessageBytes) {
      channel.send(RTCDataChannelMessage(text));
      return;
    }
    _sendChunkFrames(channel, bytes, isBinary: false);
  }

  void _sendChunkFrames(
    RTCDataChannel channel,
    Uint8List payload, {
    required bool isBinary,
  }) {
    final total = (payload.length / _chunkPayloadBytes).ceil();
    final chunkId = _uuid.v4();
    for (var index = 0; index < total; index++) {
      final start = index * _chunkPayloadBytes;
      final end = (start + _chunkPayloadBytes).clamp(0, payload.length);
      final frame = _ChunkFrame(
        id: chunkId,
        index: index,
        total: total,
        isBinary: isBinary,
        payload: payload.sublist(start, end),
      );
      channel.send(RTCDataChannelMessage(frame.toJson()));
    }
  }

  void _transition(PeerState next) {
    if (state == next) {
      return;
    }
    _stateMachine.transition(next);
    _stateController.add(next);
  }

  bool get _requiredDataChannelsOpen {
    return _openChannels.contains(PeerChannels.chat) &&
        _openChannels.contains(PeerChannels.control);
  }

  bool _isRequiredDataChannel(String channelId) {
    return channelId == PeerChannels.chat || channelId == PeerChannels.control;
  }

  void _markConnectedIfDataChannelsReady() {
    if (!_requiredDataChannelsOpen || state == PeerState.connected) {
      return;
    }
    if (state == PeerState.offering || state == PeerState.answering) {
      _transition(PeerState.connecting);
    }
    if (state == PeerState.connecting || state == PeerState.reconnecting) {
      _transition(PeerState.connected);
      _connectedController.add(null);
    }
  }

  void _wirePeerConnection(RTCPeerConnection connection) {
    connection.onDataChannel = (RTCDataChannel channel) {
      _attachChannel(channel.label ?? 'rain.remote', channel);
    };

    connection.onIceCandidate = (RTCIceCandidate candidate) {
      if (candidate.candidate == null || candidate.candidate!.isEmpty) {
        return;
      }
      _localCandidates.add(candidate);
      _iceController.add(candidate);
    };

    connection.onConnectionState = (RTCPeerConnectionState state) {
      switch (state) {
        case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
          if (this.state == PeerState.offering ||
              this.state == PeerState.answering) {
            _transition(PeerState.connecting);
          }
          _markConnectedIfDataChannelsReady();
          break;
        case RTCPeerConnectionState.RTCPeerConnectionStateConnecting:
          if (this.state == PeerState.answering) {
            _transition(PeerState.connecting);
          }
          break;
        case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
          if (this.state == PeerState.connected) {
            _transition(PeerState.reconnecting);
            _disconnectedController.add(null);
          }
          break;
        case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
          if (this.state == PeerState.reconnecting) {
            _transition(PeerState.failed);
          } else if (this.state == PeerState.connected) {
            _transition(PeerState.reconnecting);
          }
          _disconnectedController.add(null);
          break;
        case RTCPeerConnectionState.RTCPeerConnectionStateClosed:
          if (this.state != PeerState.idle) {
            _transition(PeerState.idle);
          }
          break;
        case RTCPeerConnectionState.RTCPeerConnectionStateNew:
          break;
      }
    };
  }

  void _pruneStaleChunkBuffers(DateTime now) {
    _chunkBuffers.removeWhere((_, _ChunkAccumulator accumulator) {
      return now.difference(accumulator.createdAt) > _chunkBufferTtl;
    });
  }
}

class _ChunkAccumulator {
  _ChunkAccumulator(this.total, this.isBinary, {required this.createdAt})
    : _parts = List<Uint8List?>.filled(total, null);

  final int total;
  final bool isBinary;
  final DateTime createdAt;
  final List<Uint8List?> _parts;

  bool get isComplete => _parts.every((Uint8List? part) => part != null);

  bool matches(_ChunkFrame frame) {
    return frame.total == total && frame.isBinary == isBinary;
  }

  void add(int index, Uint8List payload) {
    if (index >= 0 && index < total) {
      _parts[index] = payload;
    }
  }

  Uint8List join() {
    final parts = _parts.nonNulls.toList(growable: false);
    final totalBytes = parts.fold<int>(
      0,
      (int value, Uint8List part) => value + part.length,
    );
    final bytes = Uint8List(totalBytes);
    var offset = 0;
    for (final part in parts) {
      bytes.setRange(offset, offset + part.length, part);
      offset += part.length;
    }
    return bytes;
  }
}

class _ChunkFrame {
  const _ChunkFrame({
    required this.id,
    required this.index,
    required this.total,
    required this.isBinary,
    required this.payload,
  });

  final String id;
  final int index;
  final int total;
  final bool isBinary;
  final Uint8List payload;

  String toJson() {
    return jsonEncode(<String, Object?>{
      'type': 'chunk',
      'id': id,
      'index': index,
      'total': total,
      'isBinary': isBinary,
      'payload': base64Encode(payload),
    });
  }

  static _ChunkFrame? tryParse(String raw) {
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      return null;
    }
    if (decoded is! Map<String, dynamic> || decoded['type'] != 'chunk') {
      return null;
    }
    final id = decoded['id'];
    final index = decoded['index'];
    final total = decoded['total'];
    final payload = decoded['payload'];
    if (id is! String ||
        id.isEmpty ||
        id.length > 128 ||
        index is! int ||
        total is! int ||
        payload is! String) {
      return null;
    }
    if (total <= 0 || total > _maxChunkFrames || index < 0 || index >= total) {
      return null;
    }
    final Uint8List decodedPayload;
    try {
      decodedPayload = base64Decode(payload);
    } catch (_) {
      return null;
    }
    if (decodedPayload.lengthInBytes > _chunkPayloadBytes) {
      return null;
    }
    return _ChunkFrame(
      id: id,
      index: index,
      total: total,
      isBinary: decoded['isBinary'] as bool? ?? false,
      payload: decodedPayload,
    );
  }

  static bool hasChunkEnvelope(String raw) {
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> && decoded['type'] == 'chunk';
    } catch (_) {
      return false;
    }
  }
}
