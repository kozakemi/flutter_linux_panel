import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as status;

import '../models/wifi_models.dart';

/// WebSocket 连接状态
enum WebSocketConnectionState {
  disconnected,
  connecting,
  connected,
  reconnecting,
  error,
}

/// WebSocket 客户端服务
class WebSocketClient {
  WebSocketChannel? _channel;
  WebSocketConnectionState _state = WebSocketConnectionState.disconnected;
  Timer? _reconnectTimer;
  Timer? _heartbeatTimer;
  
  final String _url;
  final Duration _reconnectInterval;
  final Duration _heartbeatInterval;
  final Duration _requestTimeout;
  
  // 流控制器
  final StreamController<WebSocketConnectionState> _stateController = 
      StreamController<WebSocketConnectionState>.broadcast();
  final StreamController<WebSocketResponse> _responseController = 
      StreamController<WebSocketResponse>.broadcast();
  final StreamController<WebSocketEvent> _eventController = 
      StreamController<WebSocketEvent>.broadcast();
  
  // 待处理的请求
  final Map<String, Completer<WebSocketResponse>> _pendingRequests = {};
  int _requestIdCounter = 0;

  WebSocketClient({
    required String url,
    Duration reconnectInterval = const Duration(seconds: 5),
    Duration heartbeatInterval = const Duration(seconds: 30),
    Duration requestTimeout = const Duration(seconds: 10),
  }) : _url = url,
       _reconnectInterval = reconnectInterval,
       _heartbeatInterval = heartbeatInterval,
       _requestTimeout = requestTimeout;

  /// 连接状态流
  Stream<WebSocketConnectionState> get stateStream => _stateController.stream;

  /// 响应流
  Stream<WebSocketResponse> get responseStream => _responseController.stream;

  /// 事件流
  Stream<WebSocketEvent> get eventStream => _eventController.stream;

  /// 当前连接状态
  WebSocketConnectionState get state => _state;

  /// 是否已连接
  bool get isConnected => _state == WebSocketConnectionState.connected;

  /// 连接到 WebSocket 服务器
  Future<void> connect() async {
    if (_state == WebSocketConnectionState.connecting || 
        _state == WebSocketConnectionState.connected) {
      return;
    }

    _setState(WebSocketConnectionState.connecting);

    try {
      _channel = WebSocketChannel.connect(Uri.parse(_url));
      
      // 监听消息
      _channel!.stream.listen(
        _onMessage,
        onError: _onError,
        onDone: _onDisconnected,
      );

      _setState(WebSocketConnectionState.connected);
      _startHeartbeat();
      
    } catch (e) {
      _setState(WebSocketConnectionState.error);
      _scheduleReconnect();
    }
  }

  /// 断开连接
  Future<void> disconnect() async {
    _reconnectTimer?.cancel();
    _heartbeatTimer?.cancel();
    
    // 取消所有待处理的请求
    for (final completer in _pendingRequests.values) {
      completer.completeError(const SocketException('Connection closed'));
    }
    _pendingRequests.clear();

    if (_channel != null) {
      await _channel!.sink.close(status.goingAway);
      _channel = null;
    }

    _setState(WebSocketConnectionState.disconnected);
  }

  /// 发送请求并等待响应
  Future<WebSocketResponse> sendRequest(WebSocketRequest request) async {
    if (!isConnected) {
      throw const SocketException('WebSocket not connected');
    }

    // 生成请求 ID
    final requestId = request.requestId ?? _generateRequestId();
    final requestWithId = WebSocketRequest(
      type: request.type,
      requestId: requestId,
      data: request.data,
    );

    // 创建 Completer 等待响应
    final completer = Completer<WebSocketResponse>();
    _pendingRequests[requestId] = completer;

    // 设置超时
    Timer(_requestTimeout, () {
      if (_pendingRequests.containsKey(requestId)) {
        _pendingRequests.remove(requestId);
        completer.completeError(TimeoutException('Request timeout', _requestTimeout));
      }
    });

    try {
      // 发送请求
      final message = jsonEncode(requestWithId.toJson());
      _channel!.sink.add(message);
      
      return await completer.future;
    } catch (e) {
      _pendingRequests.remove(requestId);
      rethrow;
    }
  }

  /// 发送消息（不等待响应）
  void sendMessage(WebSocketMessage message) {
    if (!isConnected) {
      throw const SocketException('WebSocket not connected');
    }

    final jsonMessage = jsonEncode(message.toJson());
    _channel!.sink.add(jsonMessage);
  }

  /// 处理接收到的消息
  void _onMessage(dynamic data) {
    try {
      print('收到消息 (长度 ${data.toString().length}): $data');
      final json = jsonDecode(data as String) as Map<String, dynamic>;
      final type = json['type'] as String;

      if (type.endsWith('_response')) {
        // 处理响应
        final response = WebSocketResponse.fromJson(json);
        print('处理响应: ${response.type}, success: ${response.success}, error: ${response.error}');
        _handleResponse(response);
      } else if (type.endsWith('_event')) {
        // 处理事件
        final event = WebSocketEvent.fromJson(json);
        print('处理事件: ${event.type}');
        _eventController.add(event);
      } else {
        print('未知消息类型: $type');
      }
    } catch (e, stackTrace) {
      print('解析 WebSocket 消息错误: $e');
      print('堆栈跟踪: $stackTrace');
      print('原始消息: $data');
    }
  }

  /// 处理响应消息
  void _handleResponse(WebSocketResponse response) {
    _responseController.add(response);

    // 如果有对应的请求在等待，完成它
    if (response.requestId != null) {
      final completer = _pendingRequests.remove(response.requestId!);
      if (completer != null) {
        completer.complete(response);
        print('通过 request_id 完成请求: ${response.requestId}');
      }
    } else {
      // 如果响应没有 request_id，尝试根据类型匹配最近的请求
      // 这是为了兼容不返回 request_id 的服务器
      final responseType = response.type;
      print('处理无 request_id 的响应: $responseType');
      
      if (responseType.endsWith('_response')) {
        // 根据响应类型查找对应的请求类型
        final requestType = responseType.replaceAll('_response', '_request');
        print('查找匹配的请求类型: $requestType');
        
        // 查找最早的匹配请求（FIFO 顺序）
        String? matchingRequestId;
        int? earliestTimestamp;
        
        for (final requestId in _pendingRequests.keys) {
          // 从 request_id 中提取时间戳和类型信息
          // request_id 格式: req_<counter>_<timestamp>
          final parts = requestId.split('_');
          if (parts.length >= 3) {
            try {
              final timestamp = int.parse(parts[2]);
              // 这里可以根据需要添加更精确的类型匹配
              // 目前使用时间戳最早的请求
              if (earliestTimestamp == null || timestamp < earliestTimestamp) {
                earliestTimestamp = timestamp;
                matchingRequestId = requestId;
              }
            } catch (e) {
              // 忽略解析错误，继续处理下一个
            }
          }
        }
        
        if (matchingRequestId != null) {
          final completer = _pendingRequests.remove(matchingRequestId);
          if (completer != null) {
            completer.complete(response);
            print('通过类型匹配完成请求: $matchingRequestId -> $responseType');
          }
        } else {
          print('未找到匹配的待处理请求，当前待处理请求: ${_pendingRequests.keys.toList()}');
        }
      }
    }
  }

  /// 处理连接错误
  void _onError(dynamic error) {
    print('WebSocket error: $error');
    _setState(WebSocketConnectionState.error);
    _scheduleReconnect();
  }

  /// 处理连接断开
  void _onDisconnected() {
    print('WebSocket disconnected');
    _setState(WebSocketConnectionState.disconnected);
    _scheduleReconnect();
  }

  /// 安排重连
  void _scheduleReconnect() {
    if (_state == WebSocketConnectionState.disconnected) {
      return; // 手动断开，不重连
    }

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(_reconnectInterval, () {
      if (_state != WebSocketConnectionState.connected) {
        _setState(WebSocketConnectionState.reconnecting);
        connect();
      }
    });
  }

  /// 开始心跳
  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(_heartbeatInterval, (timer) {
      if (isConnected) {
        try {
          // 发送心跳消息（如果服务器支持 ping）
          final pingRequest = WebSocketRequest(
            type: 'ping_request',
            data: {},
          );
          sendMessage(pingRequest);
        } catch (e) {
          print('Heartbeat failed: $e');
        }
      } else {
        timer.cancel();
      }
    });
  }

  /// 设置连接状态
  void _setState(WebSocketConnectionState newState) {
    if (_state != newState) {
      _state = newState;
      _stateController.add(_state);
    }
  }

  /// 生成请求 ID
  String _generateRequestId() {
    return 'req_${++_requestIdCounter}_${DateTime.now().millisecondsSinceEpoch}';
  }

  /// 释放资源
  void dispose() {
    disconnect();
    _stateController.close();
    _responseController.close();
    _eventController.close();
  }
}