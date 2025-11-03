import 'dart:async';
import 'dart:convert';
// 为兼容 Web 环境，改用 web_socket_channel 来统一连接实现
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as status;
import 'dart:developer' as developer;
import '../models/websocket_models.dart';

/// WebSocket连接管理器
class WebSocketConnectionManager {
  final String serverUrl;
  final String path;
  final Duration reconnectInterval;
  final Duration heartbeatInterval;
  final Duration requestTimeout;
  final int maxReconnectAttempts;
  
  WebSocketChannel? _channel;
  Timer? _reconnectTimer;
  Timer? _heartbeatTimer;
  int _reconnectAttempts = 0;
  bool _isDisposed = false;
  bool _isConnecting = false;
  
  final StreamController<WebSocketConnectionState> _connectionStateController =
      StreamController<WebSocketConnectionState>.broadcast();
  final StreamController<WebSocketMessage> _messageController =
      StreamController<WebSocketMessage>.broadcast();
  final StreamController<WebSocketEvent> _eventController =
      StreamController<WebSocketEvent>.broadcast();
  
  final Map<String, Completer<WebSocketResponse>> _pendingRequests = {};
  
  WebSocketConnectionManager({
    required this.serverUrl,
    required this.path,
    this.reconnectInterval = const Duration(seconds: 5),
    this.heartbeatInterval = const Duration(seconds: 30),
    this.requestTimeout = const Duration(seconds: 10),
    this.maxReconnectAttempts = 5,
  });
  
  /// 连接状态流
  Stream<WebSocketConnectionState> get connectionStateStream =>
      _connectionStateController.stream;
  
  /// 消息流
  Stream<WebSocketMessage> get messageStream => _messageController.stream;
  
  /// 事件流
  Stream<WebSocketEvent> get eventStream => _eventController.stream;
  
  /// 当前连接状态
  WebSocketConnectionState get connectionState {
    if (_channel == null) return WebSocketConnectionState.disconnected;
    if (_isConnecting) return WebSocketConnectionState.connecting;
    // WebSocketChannel 没有 readyState，使用连接建立后的标志位由 connect() 控制
    return _isConnecting ? WebSocketConnectionState.connecting : WebSocketConnectionState.connected;
  }
  
  /// 连接到WebSocket服务器
  Future<void> connect() async {
    if (_isDisposed) {
      throw WebSocketException('连接管理器已释放');
    }
    
    if (_isConnecting || connectionState == WebSocketConnectionState.connected) {
      return;
    }
    
    _isConnecting = true;
    _updateConnectionState(WebSocketConnectionState.connecting);
    
    try {
      final uri = Uri.parse('$serverUrl$path');
      developer.log('连接到WebSocket: $uri', name: 'ConnectionManager');
      
      _channel = WebSocketChannel.connect(uri);
      _setupWebSocketListeners();
      _startHeartbeat();
      _reconnectAttempts = 0;
      _isConnecting = false;
      
      _updateConnectionState(WebSocketConnectionState.connected);
      developer.log('WebSocket连接成功: $uri', name: 'ConnectionManager');
    } catch (e, stackTrace) {
      _isConnecting = false;
      _updateConnectionState(WebSocketConnectionState.disconnected);
      
      developer.log(
        'WebSocket连接失败: $e',
        name: 'ConnectionManager',
        error: e,
        stackTrace: stackTrace,
      );
      
      _scheduleReconnect();
      rethrow;
    }
  }
  
  /// 断开连接
  Future<void> disconnect() async {
    developer.log('断开WebSocket连接', name: 'ConnectionManager');
    
    _stopReconnect();
    _stopHeartbeat();
    
    if (_channel != null) {
      try {
        await _channel!.sink.close(status.normalClosure);
      } catch (e) {
        developer.log('关闭WebSocket时发生错误: $e', name: 'ConnectionManager');
      }
      _channel = null;
    }
    
    _updateConnectionState(WebSocketConnectionState.disconnected);
  }
  
  /// 发送请求并等待响应
  Future<WebSocketResponse> sendRequest(WebSocketRequest request) async {
    if (connectionState != WebSocketConnectionState.connected) {
      throw WebSocketException('WebSocket未连接');
    }
    
    final completer = Completer<WebSocketResponse>();
    _pendingRequests[request.requestId!] = completer;
    
    // 设置请求超时
    Timer(requestTimeout, () {
      if (_pendingRequests.containsKey(request.requestId!)) {
        _pendingRequests.remove(request.requestId!);
        if (!completer.isCompleted) {
          completer.completeError(WebSocketException('请求超时: ${request.requestId}'));
        }
      }
    });
    
    try {
      final message = jsonEncode(request.toJson());
      _channel!.sink.add(message);
      
      developer.log('发送请求: ${request.type}', name: 'ConnectionManager');
      return await completer.future;
    } catch (e) {
      _pendingRequests.remove(request.requestId!);
      rethrow;
    }
  }
  
  /// 发送消息（不等待响应）
  void sendMessage(WebSocketMessage message) {
    if (connectionState != WebSocketConnectionState.connected) {
      throw WebSocketException('WebSocket未连接');
    }
    
    try {
      final jsonMessage = jsonEncode(message.toJson());
      _channel!.sink.add(jsonMessage);
      
      developer.log('发送消息: ${message.type}', name: 'ConnectionManager');
    } catch (e, stackTrace) {
      developer.log(
        '发送消息失败: $e',
        name: 'ConnectionManager',
        error: e,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }
  
  /// 释放资源
  Future<void> dispose() async {
    if (_isDisposed) return;
    
    _isDisposed = true;
    developer.log('释放WebSocket连接管理器', name: 'ConnectionManager');
    
    await disconnect();
    
    // 完成所有待处理的请求
    for (final completer in _pendingRequests.values) {
      if (!completer.isCompleted) {
        completer.completeError(WebSocketException('连接管理器已释放'));
      }
    }
    _pendingRequests.clear();
    
    await _connectionStateController.close();
    await _messageController.close();
    await _eventController.close();
  }
  
  /// 设置WebSocket监听器
  void _setupWebSocketListeners() {
    _channel!.stream.listen(
      (data) => _handleMessage(data),
      onError: (error) => _handleError(error),
      onDone: () => _handleDisconnection(),
    );
  }
  
  /// 处理接收到的消息
  void _handleMessage(dynamic data) {
    try {
      final Map<String, dynamic> json = jsonDecode(data);
      final message = WebSocketMessage.fromJson(json);
      
      developer.log('收到消息: ${message.type}', name: 'ConnectionManager');
      
      if (message is WebSocketResponse) {
        _handleResponse(message);
      } else if (message is WebSocketEvent) {
        _handleEvent(message);
      }
      
      _messageController.add(message);
    } catch (e, stackTrace) {
      developer.log(
        '处理消息时发生错误: $e',
        name: 'ConnectionManager',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }
  
  /// 处理响应消息
  void _handleResponse(WebSocketResponse response) {
    final completer = _pendingRequests.remove(response.requestId!);
    if (completer != null && !completer.isCompleted) {
      completer.complete(response);
    }
  }
  
  /// 处理事件消息
  void _handleEvent(WebSocketEvent event) {
    _eventController.add(event);
  }
  
  /// 处理错误
  void _handleError(dynamic error) {
    developer.log('WebSocket错误: $error', name: 'ConnectionManager');
    _updateConnectionState(WebSocketConnectionState.disconnected);
    _scheduleReconnect();
  }
  
  /// 处理连接断开
  void _handleDisconnection() {
    developer.log('WebSocket连接断开', name: 'ConnectionManager');
    _channel = null;
    _stopHeartbeat();
    _updateConnectionState(WebSocketConnectionState.disconnected);
    _scheduleReconnect();
  }
  
  /// 安排重连
  void _scheduleReconnect() {
    if (_isDisposed || _reconnectTimer != null) return;
    
    if (_reconnectAttempts >= maxReconnectAttempts) {
      developer.log('达到最大重连次数，停止重连', name: 'ConnectionManager');
      return;
    }
    
    _reconnectAttempts++;
    developer.log('安排重连 (${_reconnectAttempts}/$maxReconnectAttempts)', name: 'ConnectionManager');
    
    _reconnectTimer = Timer(reconnectInterval, () {
      _reconnectTimer = null;
      if (!_isDisposed) {
        connect().catchError((e) {
          developer.log('重连失败: $e', name: 'ConnectionManager');
        });
      }
    });
  }
  
  /// 停止重连
  void _stopReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
  }
  
  /// 开始心跳
  void _startHeartbeat() {
    _stopHeartbeat();
    
    _heartbeatTimer = Timer.periodic(heartbeatInterval, (timer) {
      if (connectionState == WebSocketConnectionState.connected) {
        try {
          // 发送心跳消息
          final heartbeat = WebSocketRequest(
            requestId: 'heartbeat_${DateTime.now().millisecondsSinceEpoch}',
            type: 'heartbeat',
            data: {'timestamp': DateTime.now().toIso8601String()},
          );
          sendMessage(heartbeat);
        } catch (e) {
          developer.log('发送心跳失败: $e', name: 'ConnectionManager');
        }
      }
    });
  }
  
  /// 停止心跳
  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }
  
  /// 更新连接状态
  void _updateConnectionState(WebSocketConnectionState state) {
    if (!_connectionStateController.isClosed) {
      _connectionStateController.add(state);
    }
  }
}