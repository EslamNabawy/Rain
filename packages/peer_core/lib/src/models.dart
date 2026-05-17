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
  });

  final List<Map<String, dynamic>> iceServers;
  final PlatformBridge platform;
  final bool ordered;
  final int? maxRetransmits;

  Map<String, dynamic> toRtcConfiguration() {
    return <String, dynamic>{'iceServers': iceServers};
  }

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
    this.localCandidateType,
    this.remoteCandidateType,
    this.protocol,
    this.relayProtocol,
    this.rtt,
    this.bitrate,
    this.updatedAt,
  });

  const PeerConnectionRoute.unknown({this.updatedAt})
    : kind = PeerRouteKind.unknown,
      localCandidateType = null,
      remoteCandidateType = null,
      protocol = null,
      relayProtocol = null,
      rtt = null,
      bitrate = null;

  final PeerRouteKind kind;
  final String? localCandidateType;
  final String? remoteCandidateType;
  final String? protocol;
  final String? relayProtocol;
  final double? rtt;
  final double? bitrate;
  final int? updatedAt;

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
    final localType = _candidateType(localCandidate);
    final remoteType = _candidateType(remoteCandidate);
    final kind = _routeKind(localType, remoteType);

    return PeerConnectionRoute(
      kind: kind,
      localCandidateType: localType,
      remoteCandidateType: remoteType,
      protocol:
          _stringStat(localCandidate?.values, const <String>['protocol']) ??
          _stringStat(remoteCandidate?.values, const <String>['protocol']),
      relayProtocol:
          _stringStat(localCandidate?.values, const <String>[
            'relayProtocol',
          ]) ??
          _stringStat(remoteCandidate?.values, const <String>['relayProtocol']),
      rtt: _doubleStat(selectedPair.values, const <String>[
        'currentRoundTripTime',
        'roundTripTime',
      ]),
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
  return report != null &&
      _normalizedReportType(report.type) == 'candidate-pair';
}

String _normalizedReportType(String value) {
  return value.trim().toLowerCase();
}

String? _candidateType(StatsReport? report) {
  return _stringStat(report?.values, const <String>[
    'candidateType',
    'type',
  ])?.toLowerCase();
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
  ]);
  final incoming = _doubleStat(values, const <String>[
    'availableIncomingBitrate',
  ]);
  if (outgoing == null) {
    return incoming;
  }
  if (incoming == null) {
    return outgoing;
  }
  return outgoing > incoming ? outgoing : incoming;
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
