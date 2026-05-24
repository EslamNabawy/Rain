import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:rain/application/runtime/video_call_renderers.dart';

void main() {
  test('initializes local and remote renderers once', () async {
    final factory = _FakeRendererFactory();
    final renderers = VideoCallRenderers(rendererFactory: factory);

    await renderers.ensureInitialized();
    await renderers.ensureInitialized();

    expect(factory.handles, hasLength(2));
    expect(factory.handles[0].initializeCalls, 1);
    expect(factory.handles[1].initializeCalls, 1);
    expect(renderers.state.localInitialized, isTrue);
    expect(renderers.state.remoteInitialized, isTrue);

    await renderers.dispose();
  });

  test('assigns local stream to local renderer', () async {
    final factory = _FakeRendererFactory();
    final renderers = VideoCallRenderers(rendererFactory: factory);
    final stream = _FakeMediaStream('local-stream');

    await renderers.attachLocalStream(stream);

    expect(factory.local.srcObject, same(stream));
    expect(factory.remote.srcObject, isNull);
    expect(renderers.state.hasLocalStream, isTrue);

    await renderers.dispose();
  });

  test('assigns remote stream to remote renderer', () async {
    final factory = _FakeRendererFactory();
    final renderers = VideoCallRenderers(rendererFactory: factory);
    final stream = _FakeMediaStream('remote-stream');

    await renderers.attachRemoteStream(stream);

    expect(factory.remote.srcObject, same(stream));
    expect(factory.local.srcObject, isNull);
    expect(renderers.state.hasRemoteStream, isTrue);

    await renderers.dispose();
  });

  test('clears renderer streams on hangup', () async {
    final factory = _FakeRendererFactory();
    final renderers = VideoCallRenderers(rendererFactory: factory);

    await renderers.attachLocalStream(_FakeMediaStream('local-stream'));
    await renderers.attachRemoteStream(_FakeMediaStream('remote-stream'));
    await renderers.clear();

    expect(factory.local.srcObject, isNull);
    expect(factory.remote.srcObject, isNull);
    expect(renderers.state.hasLocalStream, isFalse);
    expect(renderers.state.hasRemoteStream, isFalse);
    expect(renderers.state.localFirstFrameRendered, isFalse);
    expect(renderers.state.remoteFirstFrameRendered, isFalse);

    await renderers.dispose();
  });

  test('disposes renderers idempotently', () async {
    final factory = _FakeRendererFactory();
    final renderers = VideoCallRenderers(rendererFactory: factory);

    await renderers.ensureInitialized();
    await renderers.dispose();
    await renderers.dispose();

    expect(factory.local.disposeCalls, 1);
    expect(factory.remote.disposeCalls, 1);
  });

  test('first-frame events update state', () async {
    final factory = _FakeRendererFactory();
    final renderers = VideoCallRenderers(rendererFactory: factory);
    final states = <VideoCallRendererState>[];
    final subscription = renderers.onStateChanged.listen(states.add);

    await renderers.attachLocalStream(_FakeMediaStream('local-stream'));
    await renderers.attachRemoteStream(_FakeMediaStream('remote-stream'));
    factory.local.emitFirstFrame();
    factory.remote.emitFirstFrame();
    await pumpEventQueue();

    expect(renderers.state.localFirstFrameRendered, isTrue);
    expect(renderers.state.remoteFirstFrameRendered, isTrue);
    expect(renderers.state.localFirstFrameAt, isNotNull);
    expect(renderers.state.remoteFirstFrameAt, isNotNull);
    expect(states.any((state) => state.localFirstFrameRendered), isTrue);
    expect(states.any((state) => state.remoteFirstFrameRendered), isTrue);

    await subscription.cancel();
    await renderers.dispose();
  });

  test('remote first-frame timeout updates state', () async {
    final factory = _FakeRendererFactory();
    final renderers = VideoCallRenderers(
      rendererFactory: factory,
      remoteFirstFrameTimeout: Duration.zero,
    );

    await renderers.attachRemoteStream(_FakeMediaStream('remote-stream'));
    await pumpEventQueue();

    expect(renderers.state.remoteFirstFrameTimedOut, isTrue);
    expect(renderers.state.remoteFirstFrameTimeoutAt, isNotNull);

    await renderers.dispose();
  });
}

class _FakeRendererFactory implements VideoCallRendererFactory {
  final List<_FakeRendererHandle> handles = <_FakeRendererHandle>[];

  _FakeRendererHandle get local => handles[0];
  _FakeRendererHandle get remote => handles[1];

  @override
  VideoCallRendererHandle create() {
    final handle = _FakeRendererHandle(textureId: handles.length + 1);
    handles.add(handle);
    return handle;
  }
}

class _FakeRendererHandle implements VideoCallRendererHandle {
  _FakeRendererHandle({required this.textureId});

  @override
  final int? textureId;

  @override
  MediaStream? srcObject;

  @override
  void Function()? onFirstFrameRendered;

  int initializeCalls = 0;
  int disposeCalls = 0;

  @override
  Future<void> initialize() async {
    initializeCalls += 1;
  }

  @override
  Future<void> dispose() async {
    disposeCalls += 1;
  }

  @override
  Widget buildView({Key? key, bool mirror = false}) {
    return SizedBox(key: key);
  }

  void emitFirstFrame() {
    onFirstFrameRendered?.call();
  }
}

class _FakeMediaStream extends Fake implements MediaStream {
  _FakeMediaStream(this._id);

  final String _id;

  @override
  String get id => _id;
}
