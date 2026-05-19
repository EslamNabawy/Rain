import 'dart:convert';
import 'dart:typed_data';

class IrohEndpointInfo {
  const IrohEndpointInfo({required this.nodeId, required this.endpointAddr});

  final String nodeId;
  final String endpointAddr;
}

enum IrohConnectionRoute { unknown, direct, relay }

class IrohPathDiagnostics {
  const IrohPathDiagnostics({required this.route, this.rttMs, this.lastError});

  final IrohConnectionRoute route;
  final double? rttMs;
  final String? lastError;
}

class IrohTransportMessage {
  const IrohTransportMessage({
    required this.peerId,
    required this.channel,
    required this.payload,
    required this.receivedAt,
  });

  final String peerId;
  final String channel;
  final Object payload;
  final DateTime receivedAt;

  String? get text => payload is String ? payload as String : null;
  Uint8List? get binary => payload is Uint8List ? payload as Uint8List : null;
}

enum IrohTransportEventType { data, diagnostics, disconnected, error, unknown }

class IrohTransportEvent {
  const IrohTransportEvent({
    required this.type,
    required this.peerId,
    required this.receivedAt,
    this.channel,
    this.payload,
    this.route,
    this.rttMs,
    this.error,
  });

  factory IrohTransportEvent.fromJsonString(
    String raw, {
    DateTime Function()? now,
  }) {
    final receivedAt = (now ?? DateTime.now)();
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, Object?>) {
        return IrohTransportEvent(
          type: IrohTransportEventType.error,
          peerId: '',
          receivedAt: receivedAt,
          error: 'Malformed Iroh event.',
        );
      }
      return IrohTransportEvent.fromJson(decoded, receivedAt: receivedAt);
    } catch (_) {
      return IrohTransportEvent(
        type: IrohTransportEventType.error,
        peerId: '',
        receivedAt: receivedAt,
        error: 'Malformed Iroh event.',
      );
    }
  }

  factory IrohTransportEvent.fromJson(
    Map<String, Object?> json, {
    required DateTime receivedAt,
  }) {
    return IrohTransportEvent(
      type: _eventType(json['event_type']),
      peerId: (json['peer_id'] as String? ?? '').trim().toLowerCase(),
      channel: json['channel'] as String?,
      payload: _payload(json['payload']),
      route: json['route'] as String?,
      rttMs: _double(json['rtt_ms']),
      error: json['error'] as String?,
      receivedAt: receivedAt,
    );
  }

  final IrohTransportEventType type;
  final String peerId;
  final String? channel;
  final Uint8List? payload;
  final String? route;
  final double? rttMs;
  final String? error;
  final DateTime receivedAt;
}

IrohTransportEventType _eventType(Object? value) {
  return switch (value) {
    'data' => IrohTransportEventType.data,
    'diagnostics' => IrohTransportEventType.diagnostics,
    'disconnected' => IrohTransportEventType.disconnected,
    'error' => IrohTransportEventType.error,
    _ => IrohTransportEventType.unknown,
  };
}

Uint8List? _payload(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is Uint8List) {
    return value;
  }
  if (value is List) {
    final bytes = <int>[];
    for (final item in value) {
      if (item is! num) {
        return null;
      }
      bytes.add(item.toInt().clamp(0, 255));
    }
    return Uint8List.fromList(bytes);
  }
  return null;
}

double? _double(Object? value) {
  if (value is num) {
    return value.toDouble();
  }
  return null;
}
