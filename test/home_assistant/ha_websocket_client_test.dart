import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:demo1/home_assistant/api/ha_websocket_client.dart';

void main() {
  test('authenticates, correlates commands, and receives events', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final eventReceived = Completer<Map<String, dynamic>>();
    final requestHandled = Completer<void>();
    server.listen((request) async {
      final socket = await WebSocketTransformer.upgrade(request);
      socket.add(jsonEncode(<String, dynamic>{
        'type': 'auth_required',
        'ha_version': '2026.8.0',
      }));
      socket.listen((data) {
        final message = jsonDecode('$data') as Map<String, dynamic>;
        if (message['type'] == 'auth') {
          expect(message['access_token'], 'test-token');
          socket.add(jsonEncode(<String, dynamic>{
            'type': 'auth_ok',
            'ha_version': '2026.8.0',
          }));
          return;
        }
        final id = message['id'] as int;
        socket.add(jsonEncode(<String, dynamic>{
          'id': id,
          'type': 'result',
          'success': true,
          'result': <Map<String, dynamic>>[
            <String, dynamic>{'entity_id': 'light.test', 'state': 'on'},
          ],
        }));
        socket.add(jsonEncode(<String, dynamic>{
          'id': 99,
          'type': 'event',
          'event': <String, dynamic>{'event_type': 'state_changed'},
        }));
        if (!requestHandled.isCompleted) requestHandled.complete();
      });
    });

    final client = HaWebSocketClient();
    client.onEvent = eventReceived.complete;
    final version = await client.connect(
      Uri.parse('ws://127.0.0.1:${server.port}/api/websocket'),
      'test-token',
    );
    expect(version, '2026.8.0');
    final result = await client.command(
      const <String, dynamic>{'type': 'get_states'},
    );
    expect((result as List).first['entity_id'], 'light.test');
    expect((await eventReceived.future)['type'], 'event');
    await requestHandled.future;
    await client.close();
    await server.close(force: true);
  });

  test('reports authentication failure', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final socket = await WebSocketTransformer.upgrade(request);
      socket.add(jsonEncode(<String, dynamic>{'type': 'auth_required'}));
      socket.listen((_) {
        socket.add(jsonEncode(<String, dynamic>{
          'type': 'auth_invalid',
          'message': 'Invalid access token',
        }));
      });
    });

    final client = HaWebSocketClient();
    await expectLater(
      client.connect(
        Uri.parse('ws://127.0.0.1:${server.port}/api/websocket'),
        'bad-token',
      ),
      throwsA(isA<HaApiException>()),
    );
    await client.close();
    await server.close(force: true);
  });
}
