import 'dart:convert';
import 'dart:io';

import 'package:client/models/call_state.dart';
import 'package:client/services/signaling_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late HttpServer server;
  late SignalingService service;
  final sockets = <WebSocket>[];
  final messages = <Map<String, dynamic>>[];
  late void Function(WebSocket socket, Map<String, dynamic> data) respond;
  Future<void> until(bool Function() condition) async {
    final stop = DateTime.now().add(const Duration(seconds: 3));
    while (!condition()) {
      if (DateTime.now().isAfter(stop)) fail('Condition timed out');
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  setUp(() async {
    sockets.clear();
    messages.clear();
    service = SignalingService(
      heartbeatInterval: const Duration(milliseconds: 20),
      heartbeatTimeout: const Duration(milliseconds: 60),
      registrationTimeout: const Duration(milliseconds: 80),
    );
    respond = (socket, data) {};
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final socket = await WebSocketTransformer.upgrade(request);
      sockets.add(socket);
      socket.listen((raw) {
        final data = jsonDecode(raw as String) as Map<String, dynamic>;
        messages.add(data);
        respond(socket, data);
      });
    });
  });
  tearDown(() async {
    await service.dispose();
    for (final socket in sockets) {
      await socket.close();
    }
    await server.close(force: true);
  });
  String url() => 'ws://127.0.0.1:${server.port}';
  void acknowledge(WebSocket socket, Map<String, dynamic> data) {
    if (data['type'] == 'register') {
      socket.add(
        jsonEncode({
          'type': 'registered',
          'userId': data['userId'],
          'onlineUsers': [],
        }),
      );
    }
    if (data['type'] == 'ping') socket.add('{"type":"pong"}');
  }

  test(
    'socket open is not online until registration is acknowledged',
    () async {
      await service.connect(url(), 'alice');
      await until(() => messages.isNotEmpty);
      expect(service.isConnected, isFalse);
      acknowledge(sockets.single, messages.first);
      await until(() => service.isConnected);
      expect(messages.first['userId'], 'alice');
    },
  );
  test('rejected registration stops automatic reconnect', () async {
    final statuses = <SignalingStatus>[];
    final sub = service.statusStream.listen(statuses.add);
    respond = (socket, data) {
      if (data['type'] == 'register') {
        socket.add('{"type":"error","message":"Unauthorized"}');
      }
    };
    await service.connect(url(), 'alice');
    await until(() => statuses.contains(SignalingStatus.error));
    service.checkAndReconnect();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(service.isConnected, isFalse);
    expect(sockets.length, 1);
    expect(statuses, isNot(contains(SignalingStatus.reconnecting)));
    await sub.cancel();
  });
  test(
    'conflicting login stops retrying and supports explicit recovery',
    () async {
      respond = acknowledge;
      await service.connect(url(), 'alice');
      await until(() => service.isConnected);
      sockets.first.add('{"type":"conflict"}');
      await until(() => !service.isConnected);
      service.checkAndReconnect();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(sockets.length, 1);
      await service.connect(url(), 'other');
      await until(() => service.isConnected);
      expect(service.myUserId, 'other');
    },
  );
  test(
    'unresponsive heartbeat leaves online state and schedules reconnect',
    () async {
      respond = (socket, data) {
        if (data['type'] == 'register') acknowledge(socket, data);
      };
      final states = <SignalingStatus>[];
      final sub = service.statusStream.listen(states.add);
      await service.connect(url(), 'alice');
      await until(() => service.isConnected);
      await until(() => states.contains(SignalingStatus.reconnecting));
      expect(service.isConnected, isFalse);
      await sub.cancel();
    },
  );
  test('registration timeout cannot leave UI connecting forever', () async {
    final states = <SignalingStatus>[];
    final sub = service.statusStream.listen(states.add);
    await service.connect(url(), 'alice');
    await until(() => states.contains(SignalingStatus.reconnecting));
    expect(service.isConnected, isFalse);
    await sub.cancel();
  });
  test(
    'overlapping connect intents register only the latest identity',
    () async {
      respond = acknowledge;
      await Future.wait([
        service.connect(url(), 'old'),
        service.connect(url(), 'new'),
      ]);
      await until(() => service.isConnected);
      expect(
        messages.where((m) => m['type'] == 'register').map((m) => m['userId']),
        ['new'],
      );
    },
  );
}
