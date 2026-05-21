import 'dart:async';

import 'connection_command_models.dart';
import 'connection_command_orchestrator.dart';
import 'connection_run_token.dart';

class FakeConnectionTransportCall {
  const FakeConnectionTransportCall({
    required this.peerId,
    required this.layer,
    required this.runId,
    required this.generation,
  });

  final String peerId;
  final ConnectionLayer layer;
  final String runId;
  final int generation;
}

class FakeConnectionTransport implements ConnectionCommandTransport {
  FakeConnectionTransport({
    Map<ConnectionLayer, List<ConnectionLayerResult>>? scriptedResults,
  }) : _scriptedResults = scriptedResults == null
           ? <ConnectionLayer, List<ConnectionLayerResult>>{}
           : scriptedResults.map(
               (key, value) => MapEntry(key, <ConnectionLayerResult>[...value]),
             ),
       _hang = false,
       _cancelCompleter = null;

  FakeConnectionTransport.hanging({Completer<void>? cancelCompleter})
    : _scriptedResults = <ConnectionLayer, List<ConnectionLayerResult>>{},
      _hang = true,
      _cancelCompleter = cancelCompleter;

  final Map<ConnectionLayer, List<ConnectionLayerResult>> _scriptedResults;
  final bool _hang;
  final Completer<void>? _cancelCompleter;
  final List<FakeConnectionTransportCall> calls =
      <FakeConnectionTransportCall>[];
  final List<ConnectionLayer> cancelCalls = <ConnectionLayer>[];

  int _pending = 0;
  int _lastObservedCallCount = -1;

  @override
  Future<ConnectionLayerResult> runLayer({
    required String peerId,
    required ConnectionLayer layer,
    required ConnectionRunToken token,
    required Duration timeout,
  }) async {
    if (token.isCanceled) {
      return const ConnectionLayerResult.failed(
        ConnectionFailureCode.userCanceled,
      );
    }
    _pending += 1;
    recordLayer(peerId: peerId, layer: layer, token: token);
    try {
      if (_hang) {
        return await Completer<ConnectionLayerResult>().future;
      }
      final queued = _scriptedResults[layer];
      if (queued == null || queued.isEmpty) {
        return const ConnectionLayerResult.succeeded();
      }
      return queued.removeAt(0);
    } finally {
      _pending -= 1;
    }
  }

  @override
  Future<void> cancelLayer({
    required String peerId,
    required ConnectionLayer layer,
    required ConnectionRunToken token,
  }) async {
    cancelCalls.add(layer);
    await _cancelCompleter?.future;
  }

  void recordLayer({
    required String peerId,
    required ConnectionLayer layer,
    required ConnectionRunToken token,
  }) {
    if (token.isCanceled) {
      return;
    }
    calls.add(
      FakeConnectionTransportCall(
        peerId: peerId,
        layer: layer,
        runId: token.runId,
        generation: token.generation,
      ),
    );
  }

  Future<void> waitForIdle() async {
    var stableIdleTicks = 0;
    for (var index = 0; index < 50; index += 1) {
      await Future<void>.delayed(Duration.zero);
      final callCount = calls.length;
      if (_pending == 0 && callCount == _lastObservedCallCount) {
        stableIdleTicks += 1;
        if (stableIdleTicks >= 2) {
          return;
        }
      } else {
        stableIdleTicks = 0;
      }
      _lastObservedCallCount = callCount;
    }
  }
}
