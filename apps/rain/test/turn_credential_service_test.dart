import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rain/infrastructure/services/turn_credential_service.dart';

Future<HttpServer> _broker(List<String?> seenAuthHeaders) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((HttpRequest request) async {
    seenAuthHeaders.add(request.headers.value(HttpHeaders.authorizationHeader));
    await utf8.decoder.bind(request).join();
    request.response
      ..statusCode = 200
      ..headers.contentType = ContentType.json
      ..write(
        jsonEncode(<String, Object?>{
          'ttlSeconds': 3600,
          'iceServers': <Object?>[
            <String, Object?>{
              'urls': <String>['turn:turn.example.test:3478'],
              'username': 'u',
              'credential': 'c',
            },
          ],
        }),
      );
    await request.response.close();
  });
  return server;
}

void main() {
  test('sends the injected bearer token to the broker', () async {
    final seen = <String?>[];
    final server = await _broker(seen);
    addTearDown(() => server.close(force: true));
    final service = TurnCredentialService(
      baseIceServers: const <Map<String, dynamic>>[],
      brokerUrl: 'http://127.0.0.1:${server.port}/turn',
      idTokenProvider: () async => 'token-123',
    );
    addTearDown(service.dispose);

    final servers = await service.iceServers();

    expect(seen, <String?>['Bearer token-123']);
    expect(
      servers.any((Map<String, dynamic> s) => s.toString().contains('turn:')),
      isTrue,
    );
  });

  test('omits the authorization header when no token is available', () async {
    final seen = <String?>[];
    final server = await _broker(seen);
    addTearDown(() => server.close(force: true));
    final service = TurnCredentialService(
      baseIceServers: const <Map<String, dynamic>>[],
      brokerUrl: 'http://127.0.0.1:${server.port}/turn',
      idTokenProvider: () async => null,
    );
    addTearDown(service.dispose);

    await service.iceServers();

    expect(seen, <String?>[null]);
  });
}
