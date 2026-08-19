import 'dart:async';
import 'dart:convert';
import 'dart:io';

typedef HaEventHandler = void Function(Map<String, dynamic> message);
typedef HaDisconnectHandler = void Function(Object? error);

class HaWebSocketClient {
  WebSocket? _socket;
  StreamSubscription<dynamic>? _subscription;
  final Map<int, Completer<dynamic>> _pending = <int, Completer<dynamic>>{};
  int _nextId = 1;
  Completer<void>? _authentication;
  bool _closing = false;

  HaEventHandler? onEvent;
  HaDisconnectHandler? onDisconnected;

  bool get connected => _socket != null;

  Future<String> connect(Uri uri, String token) async {
    await close();
    _closing = false;
    final socket = await WebSocket.connect(uri.toString()).timeout(
      const Duration(seconds: 8),
    );
    socket.pingInterval = const Duration(seconds: 20);
    _socket = socket;
    final authentication = Completer<void>();
    _authentication = authentication;
    var version = '';
    _subscription = socket.listen(
      (data) {
        final message = _decode(data);
        if (message == null) return;
        final type = message['type'];
        if (type == 'auth_required') {
          version = message['ha_version'] as String? ?? '';
          socket.add(jsonEncode(<String, dynamic>{
            'type': 'auth',
            'access_token': token,
          }));
        } else if (type == 'auth_ok') {
          version = message['ha_version'] as String? ?? version;
          if (!authentication.isCompleted) authentication.complete();
        } else if (type == 'auth_invalid') {
          final error = HaApiException(
            message['message'] as String? ?? 'Home Assistant 认证失败',
          );
          if (!authentication.isCompleted) {
            authentication.completeError(error);
          }
        } else if (type == 'result') {
          final id = message['id'];
          if (id is! int) return;
          final pending = _pending.remove(id);
          if (pending == null) return;
          if (message['success'] == true) {
            pending.complete(message['result']);
          } else {
            final error = message['error'];
            final detail = error is Map
                ? '${error['message'] ?? error['code'] ?? '请求失败'}'
                : 'Home Assistant 请求失败';
            pending.completeError(HaApiException(detail));
          }
        } else if (type == 'event') {
          onEvent?.call(message);
        }
      },
      onDone: () => _handleDisconnect(null),
      onError: (Object error) => _handleDisconnect(error),
      cancelOnError: true,
    );
    await authentication.future.timeout(const Duration(seconds: 8));
    return version;
  }

  Future<dynamic> command(Map<String, dynamic> command) async {
    final socket = _socket;
    if (socket == null) throw const HaApiException('Home Assistant 尚未连接');
    final id = _nextId++;
    final completer = Completer<dynamic>();
    _pending[id] = completer;
    socket.add(jsonEncode(<String, dynamic>{'id': id, ...command}));
    try {
      return await completer.future.timeout(const Duration(seconds: 12));
    } finally {
      _pending.remove(id);
    }
  }

  Future<void> close() async {
    _closing = true;
    final socket = _socket;
    _socket = null;
    await _subscription?.cancel();
    _subscription = null;
    await socket?.close();
    _failPending(const HaApiException('连接已关闭'));
  }

  Map<String, dynamic>? _decode(dynamic data) {
    try {
      final value = jsonDecode(data is String ? data : utf8.decode(data));
      return value is Map<String, dynamic> ? value : null;
    } catch (_) {
      return null;
    }
  }

  void _handleDisconnect(Object? error) {
    _socket = null;
    _subscription = null;
    final failure = error ?? const HaApiException('连接已断开');
    final authentication = _authentication;
    if (authentication != null && !authentication.isCompleted) {
      authentication.completeError(failure);
    }
    _failPending(failure);
    if (!_closing) onDisconnected?.call(error);
  }

  void _failPending(Object error) {
    for (final completer in _pending.values) {
      if (!completer.isCompleted) completer.completeError(error);
    }
    _pending.clear();
  }
}

class HaApiException implements Exception {
  const HaApiException(this.message);

  final String message;

  @override
  String toString() => message;
}
