import 'dart:typed_data';

import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'platform_bridge.dart';

enum PeerState {
  idle,
  ready,
  offering,
  answering,
  connecting,
  connected,
  reconnecting,
  failed,
}

enum PeerIceTransportPolicy { all, relayOnly }

enum PeerAddressFamily { unknown, ipv4, ipv6, mixed }

final class PeerChannels {
  static const chat = 'rain.chat';
  static const control = 'rain.ctrl';
  static const file = 'rain.file';

  const PeerChannels._();
}

class PeerConfig {
  const PeerConfig({
    required this.iceServers,
    required this.platform,
    this.ordered = true,
    this.maxRetransmits,
    this.iceTransportPolicy = PeerIceTransportPolicy.all,
  });

  final List<Map<String, dynamic>> iceServers;
  final PlatformBridge platform;
  final bool ordered;
  final int? maxRetransmits;
  final PeerIceTransportPolicy iceTransportPolicy;

  Map<String, dynamic> toRtcConfiguration() {
    return <String, dynamic>{
      'iceServers': iceServers,
      'iceTransportPolicy': switch (iceTransportPolicy) {
        PeerIceTransportPolicy.all => 'all',
        PeerIceTransportPolicy.relayOnly => 'relay',
      },
    };
  }

  PeerConfig copyWith({
    List<Map<String, dynamic>>? iceServers,
    PlatformBridge? platform,
    bool? ordered,
    int? maxRetransmits,
    PeerIceTransportPolicy? iceTransportPolicy,
  }) {
    return PeerConfig(
      iceServers: iceServers ?? this.iceServers,
      platform: platform ?? this.platform,
      ordered: ordered ?? this.ordered,
      maxRetransmits: maxRetransmits ?? this.maxRetransmits,
      iceTransportPolicy: iceTransportPolicy ?? this.iceTransportPolicy,
    );
  }

  bool get hasRelayServer => iceServers.any((Map<String, dynamic> server) {
    final urls = server['urls'];
    final iterable = urls is Iterable ? urls : <Object?>[urls];
    return iterable.whereType<Object>().any((Object url) {
      final normalized = url.toString().trim().toLowerCase();
      return normalized.startsWith('turn:') || normalized.startsWith('turns:');
    });
  });

  RTCDataChannelInit defaultChannelOptions() {
    final options = RTCDataChannelInit()..ordered = ordered;
    if (maxRetransmits != null) {
      options.maxRetransmits = maxRetransmits!;
    }
    return options;
  }
}

class PeerMessage {
  const PeerMessage({
    required this.channelId,
    required this.data,
    required this.receivedAt,
    this.peerId,
  });

  final String channelId;
  final Object? data;
  final DateTime receivedAt;
  final String? peerId;

  String? get text => data is String ? data! as String : null;
  Uint8List? get binary => data is Uint8List ? data! as Uint8List : null;
}

enum PeerRouteKind { unknown, direct, relay }

class PeerConnectionRoute {
  const PeerConnectionRoute({
    required this.kind,
    this.selectedCandidatePairId,
    this.localCandidateType,
    this.remoteCandidateType,
    this.localAddressFamily = PeerAddressFamily.unknown,
    this.remoteAddressFamily = PeerAddressFamily.unknown,
    this.protocol,
    this.relayProtocol,
    this.rtt,
    this.bitrate,
    this.updatedAt,
  });

  const PeerConnectionRoute.unknown({this.updatedAt})
    : kind = PeerRouteKind.unknown,
      selectedCandidatePairId = null,
      localCandidateType = null,
      remoteCandidateType = null,
      localAddressFamily = PeerAddressFamily.unknown,
      remoteAddressFamily = PeerAddressFamily.unknown,
      protocol = null,
      relayProtocol = null,
      rtt = null,
      bitrate = null;

  final PeerRouteKind kind;
  final String? selectedCandidatePairId;
  final String? localCandidateType;
  final String? remoteCandidateType;
  final PeerAddressFamily localAddressFamily;
  final PeerAddressFamily remoteAddressFamily;
  final String? protocol;
  final String? relayProtocol;
  final double? rtt;
  final double? bitrate;
  final int? updatedAt;

  PeerAddressFamily get addressFamily {
    if (localAddressFamily == remoteAddressFamily) {
      return localAddressFamily;
    }
    if (localAddressFamily == PeerAddressFamily.unknown) {
      return remoteAddressFamily;
    }
    if (remoteAddressFamily == PeerAddressFamily.unknown) {
      return localAddressFamily;
    }
    return PeerAddressFamily.mixed;
  }

  static PeerConnectionRoute fromStats(
    Iterable<StatsReport> reports, {
    int? updatedAt,
  }) {
    final byId = <String, StatsReport>{
      for (final report in reports)
        if (report.id.isNotEmpty) report.id: report,
    };

    final selectedPair = _selectedCandidatePair(reports, byId);
    if (selectedPair == null) {
      return PeerConnectionRoute.unknown(updatedAt: updatedAt);
    }

    final localCandidateId = _stringStat(selectedPair.values, const <String>[
      'localCandidateId',
      'localCandidateID',
    ]);
    final remoteCandidateId = _stringStat(selectedPair.values, const <String>[
      'remoteCandidateId',
      'remoteCandidateID',
    ]);
    final localCandidate = localCandidateId == null
        ? null
        : byId[localCandidateId];
    final remoteCandidate = remoteCandidateId == null
        ? null
        : byId[remoteCandidateId];
    final localType =
        _candidateType(localCandidate) ??
        _candidateTypeFromPair(selectedPair, const <String>[
          'localCandidateType',
          'googLocalCandidateType',
        ]);
    final remoteType =
        _candidateType(remoteCandidate) ??
        _candidateTypeFromPair(selectedPair, const <String>[
          'remoteCandidateType',
          'googRemoteCandidateType',
        ]);
    final kind = _routeKind(localType, remoteType);

    return PeerConnectionRoute(
      kind: kind,
      selectedCandidatePairId: selectedPair.id,
      localCandidateType: localType,
      remoteCandidateType: remoteType,
      localAddressFamily:
          _addressFamily(localCandidate, selectedPair, const <String>[
            'localAddress',
            'localIp',
            'localIP',
            'localCandidateAddress',
            'googLocalAddress',
          ]),
      remoteAddressFamily:
          _addressFamily(remoteCandidate, selectedPair, const <String>[
            'remoteAddress',
            'remoteIp',
            'remoteIP',
            'remoteCandidateAddress',
            'googRemoteAddress',
          ]),
      protocol:
          _stringStat(localCandidate?.values, const <String>['protocol']) ??
          _stringStat(remoteCandidate?.values, const <String>['protocol']) ??
          _stringStat(selectedPair.values, const <String>[
            'protocol',
            'googTransportType',
          ]),
      relayProtocol:
          _stringStat(localCandidate?.values, const <String>[
            'relayProtocol',
          ]) ??
          _stringStat(remoteCandidate?.values, const <String>[
            'relayProtocol',
          ]) ??
          _stringStat(selectedPair.values, const <String>['relayProtocol']),
      rtt: _selectedRtt(selectedPair.values),
      bitrate: _selectedBitrate(selectedPair.values),
      updatedAt: updatedAt,
    );
  }
}

StatsReport? _selectedCandidatePair(
  Iterable<StatsReport> reports,
  Map<String, StatsReport> byId,
) {
  String? selectedPairId;
  for (final report in reports) {
    if (_normalizedReportType(report.type) != 'transport') {
      continue;
    }
    selectedPairId = _stringStat(report.values, const <String>[
      'selectedCandidatePairId',
      'selectedCandidatePairID',
    ]);
    if (selectedPairId != null) {
      break;
    }
  }
  final selectedFromTransport = selectedPairId == null
      ? null
      : byId[selectedPairId];
  if (_isCandidatePair(selectedFromTransport)) {
    return selectedFromTransport;
  }

  for (final report in reports) {
    if (!_isCandidatePair(report)) {
      continue;
    }
    if (_boolStat(report.values, const <String>['selected']) == true ||
        _boolStat(report.values, const <String>['googActiveConnection']) ==
            true) {
      return report;
    }
  }

  for (final report in reports) {
    if (!_isCandidatePair(report)) {
      continue;
    }
    final state = _stringStat(report.values, const <String>['state']);
    final nominated = _boolStat(report.values, const <String>['nominated']);
    if (state == 'succeeded' && nominated == true) {
      return report;
    }
  }

  for (final report in reports) {
    if (!_isCandidatePair(report)) {
      continue;
    }
    final state = _stringStat(report.values, const <String>['state']);
    if (state == 'succeeded') {
      return report;
    }
  }

  return null;
}

bool _isCandidatePair(StatsReport? report) {
  if (report == null) {
    return false;
  }
  final compactType = _normalizedReportType(
    report.type,
  ).replaceAll(RegExp(r'[-_\s]'), '');
  return compactType == 'candidatepair' || compactType == 'googcandidatepair';
}

String _normalizedReportType(String value) {
  return value.trim().toLowerCase();
}

String? _candidateType(StatsReport? report) {
  return _normalizeCandidateType(
    _stringStat(report?.values, const <String>['candidateType', 'type']),
  );
}

String? _candidateTypeFromPair(StatsReport report, Iterable<String> keys) {
  return _normalizeCandidateType(_stringStat(report.values, keys));
}

PeerAddressFamily _addressFamily(
  StatsReport? candidate,
  StatsReport selectedPair,
  Iterable<String> selectedPairKeys,
) {
  return _addressFamilyFromValues(candidate?.values, const <String>[
        'address',
        'ip',
        'ipAddress',
        'networkAddress',
        'transportAddress',
      ]) ??
      _addressFamilyFromCandidateLine(
        _stringStat(candidate?.values, const <String>['candidate']),
      ) ??
      _addressFamilyFromValues(selectedPair.values, selectedPairKeys) ??
      PeerAddressFamily.unknown;
}

PeerAddressFamily? _addressFamilyFromValues(
  Map<dynamic, dynamic>? values,
  Iterable<String> keys,
) {
  return _addressFamilyFromAddress(_stringStat(values, keys));
}

PeerAddressFamily? _addressFamilyFromCandidateLine(String? value) {
  final candidate = value?.trim();
  if (candidate == null || candidate.isEmpty) {
    return null;
  }
  final normalized = candidate.startsWith('a=')
      ? candidate.substring(2).trim()
      : candidate;
  final parts = normalized.split(RegExp(r'\s+'));
  if (parts.length < 6 || !parts.first.startsWith('candidate:')) {
    return null;
  }
  return _addressFamilyFromAddress(parts[4]);
}

PeerAddressFamily? _addressFamilyFromAddress(String? value) {
  var text = value?.trim().toLowerCase();
  if (text == null || text.isEmpty || text.endsWith('.local')) {
    return null;
  }

  final bracketedIpv6 = RegExp(r'^\[([^\]]+)\](?::\d+)?$').firstMatch(text);
  if (bracketedIpv6 != null) {
    final bracketedAddress = bracketedIpv6.group(1);
    if (bracketedAddress != null) {
      text = bracketedAddress;
    }
  }

  if (_isIpv4Address(text)) {
    return PeerAddressFamily.ipv4;
  }

  final ipv4WithPort = RegExp(
    r'^((?:\d{1,3}\.){3}\d{1,3})(?::\d+)?$',
  ).firstMatch(text);
  if (ipv4WithPort != null) {
    final ipv4Address = ipv4WithPort.group(1);
    if (ipv4Address != null && _isIpv4Address(ipv4Address)) {
      return PeerAddressFamily.ipv4;
    }
  }

  final withoutZone = text.split('%').first;
  if (withoutZone.contains(':') &&
      RegExp(r'^[0-9a-f:.]+$').hasMatch(withoutZone)) {
    return PeerAddressFamily.ipv6;
  }

  return null;
}

bool _isIpv4Address(String value) {
  final parts = value.split('.');
  if (parts.length != 4) {
    return false;
  }
  for (final part in parts) {
    if (part.isEmpty || !RegExp(r'^\d{1,3}$').hasMatch(part)) {
      return false;
    }
    final octet = int.tryParse(part);
    if (octet == null || octet > 255) {
      return false;
    }
  }
  return true;
}

String? _normalizeCandidateType(String? value) {
  final normalized = value?.trim().toLowerCase();
  return switch (normalized) {
    'local' => 'host',
    'stun' => 'srflx',
    'serverreflexive' => 'srflx',
    'peerreflexive' => 'prflx',
    'relay' || 'relayed' => 'relay',
    'host' || 'srflx' || 'prflx' => normalized,
    _ => normalized,
  };
}

PeerRouteKind _routeKind(String? localType, String? remoteType) {
  if (localType == 'relay' || remoteType == 'relay') {
    return PeerRouteKind.relay;
  }
  const directTypes = <String>{'host', 'srflx', 'prflx'};
  if (localType != null &&
      remoteType != null &&
      directTypes.contains(localType) &&
      directTypes.contains(remoteType)) {
    return PeerRouteKind.direct;
  }
  return PeerRouteKind.unknown;
}

String? _stringStat(Map<dynamic, dynamic>? values, Iterable<String> keys) {
  if (values == null) {
    return null;
  }
  for (final key in keys) {
    final value = values[key];
    if (value == null) {
      continue;
    }
    final text = value.toString().trim();
    if (text.isNotEmpty) {
      return text;
    }
  }
  return null;
}

bool? _boolStat(Map<dynamic, dynamic> values, Iterable<String> keys) {
  for (final key in keys) {
    final value = values[key];
    if (value is bool) {
      return value;
    }
    if (value is num) {
      return value != 0;
    }
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      if (normalized == 'true' || normalized == '1') {
        return true;
      }
      if (normalized == 'false' || normalized == '0') {
        return false;
      }
    }
  }
  return null;
}

double? _doubleStat(Map<dynamic, dynamic> values, Iterable<String> keys) {
  for (final key in keys) {
    final value = values[key];
    if (value is num) {
      return value.toDouble();
    }
    if (value is String) {
      return double.tryParse(value.trim());
    }
  }
  return null;
}

double? _selectedBitrate(Map<dynamic, dynamic> values) {
  final outgoing = _doubleStat(values, const <String>[
    'availableOutgoingBitrate',
    'googAvailableSendBandwidth',
  ]);
  final incoming = _doubleStat(values, const <String>[
    'availableIncomingBitrate',
    'googAvailableReceiveBandwidth',
  ]);
  if (outgoing == null) {
    return incoming;
  }
  if (incoming == null) {
    return outgoing;
  }
  return outgoing > incoming ? outgoing : incoming;
}

double? _selectedRtt(Map<dynamic, dynamic> values) {
  final standard = _doubleStat(values, const <String>[
    'currentRoundTripTime',
    'roundTripTime',
  ]);
  if (standard != null) {
    return standard;
  }
  final legacyMs = _doubleStat(values, const <String>['googRtt']);
  return legacyMs == null ? null : legacyMs / 1000;
}

abstract class PeerCore {
  Future<void> init(PeerConfig config);
  Future<void> destroy();

  Future<RTCSessionDescription> createOffer();
  Future<RTCSessionDescription> setOffer(RTCSessionDescription offer);
  Future<void> setAnswer(RTCSessionDescription answer);
  Future<void> addIceCandidate(RTCIceCandidate candidate);
  List<RTCIceCandidate> getLocalCandidates();

  void send(String channelId, dynamic data);
  Future<void> openChannel(String channelId, {RTCDataChannelInit? opts});
  Future<void> closeChannel(String channelId);
  Future<int> bufferedAmount(String channelId);
  bool isChannelOpen(String channelId);
  Future<PeerConnectionRoute> currentRoute();

  Stream<RTCIceCandidate> get onIceCandidate;
  Stream<void> get onConnected;
  Stream<void> get onDisconnected;
  Stream<PeerMessage> get onMessage;
  Stream<String> get onChannelOpen;
  Stream<String> get onChannelClose;
  Stream<PeerState> get onStateChange;

  PeerState get state;
}

typedef PeerCoreFactory = PeerCore Function();
