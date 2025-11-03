import 'dart:async';
import 'dart:developer' as developer;
import '../models/websocket_models.dart';
import 'websocket_module.dart';
import 'websocket_connection_manager.dart';
import 'websocket_config.dart';

/// WebSocket模块基础实现类
abstract class WebSocketBaseModule implements WebSocketModule {
  late final WebSocketConnectionManager _connectionManager;
  late final StreamController<ModuleEvent> _eventController;
  bool _isInitialized = false;
  bool _isDisposed = false;
  
  @override
  String get moduleId;
  
  @override
  String get websocketPath;
  
  /// 获取模块配置
  ModuleConfig get moduleConfig {
    return ModuleConfigRegistry.getConfig(moduleId) ??
        ModuleConfig(
          moduleId: moduleId,
          websocketPath: websocketPath,
          serverUrl: WebSocketConfig.defaultServerUrl,
          autoStart: true,
        );
  }
  
  @override
  Stream<WebSocketConnectionState> get connectionStateStream =>
      _connectionManager.connectionStateStream;
  
  @override
  Stream<ModuleEvent> get eventStream => _eventController.stream;
  
  @override
  Future<void> initialize() async {
    if (_isInitialized) {
      developer.log('模块已初始化: $moduleId', name: 'BaseModule');
      return;
    }
    
    developer.log('初始化模块: $moduleId', name: 'BaseModule');
    
    _eventController = StreamController<ModuleEvent>.broadcast();
    
    final config = moduleConfig;
    _connectionManager = WebSocketConnectionManager(
      serverUrl: config.serverUrl,
      path: config.websocketPath,
      reconnectInterval: config.reconnectInterval,
      heartbeatInterval: config.heartbeatInterval,
      requestTimeout: config.requestTimeout,
      maxReconnectAttempts: config.maxReconnectAttempts,
    );
    
    // 监听连接状态变化
    _connectionManager.connectionStateStream.listen(_onConnectionStateChanged);
    
    // 监听事件消息
    _connectionManager.eventStream.listen(_onEventReceived);
    
    // 执行模块特定的初始化
    await onInitialize();
    
    // 连接到WebSocket服务器（首次连接失败不再抛出，让模块以离线模式运行并自动重连）
    try {
      await _connectionManager.connect();
    } catch (e, stackTrace) {
      developer.log(
        '首次连接失败，模块将以离线模式运行并自动重连: $e',
        name: 'BaseModule',
        error: e,
        stackTrace: stackTrace,
      );
      // 不抛出异常，允许上层完成模块注册与后续重连
    }
    
    _isInitialized = true;
    developer.log('模块初始化完成: $moduleId', name: 'BaseModule');
  }
  
  @override
  Future<void> dispose() async {
    if (_isDisposed) return;
    
    developer.log('释放模块: $moduleId', name: 'BaseModule');
    
    _isDisposed = true;
    
    // 执行模块特定的清理
    await onDispose();
    
    // 释放连接管理器
    await _connectionManager.dispose();
    
    // 关闭事件流
    await _eventController.close();
    
    _isInitialized = false;
    developer.log('模块释放完成: $moduleId', name: 'BaseModule');
  }
  
  @override
  Future<WebSocketResponse> handleMessage(WebSocketRequest request) async {
    if (!_isInitialized || _isDisposed) {
      throw ModuleException(moduleId, '模块未初始化或已释放');
    }
    
    try {
      return await onHandleMessage(request);
    } catch (e, stackTrace) {
      developer.log(
        '处理消息失败: ${request.type}',
        name: 'BaseModule',
        error: e,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }
  
  @override
  void handleEvent(WebSocketEvent event) {
    if (!_isInitialized || _isDisposed) {
      developer.log('模块未初始化或已释放，忽略事件: ${event.type}', name: 'BaseModule');
      return;
    }
    
    try {
      onHandleEvent(event);
    } catch (e, stackTrace) {
      developer.log(
        '处理事件失败: ${event.type}',
        name: 'BaseModule',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }
  
  /// 发送请求并等待响应
  Future<WebSocketResponse> sendRequest(WebSocketRequest request) async {
    if (!_isInitialized || _isDisposed) {
      throw ModuleException(moduleId, '模块未初始化或已释放');
    }
    
    return await _connectionManager.sendRequest(request);
  }
  
  /// 发送消息（不等待响应）
  void sendMessage(WebSocketMessage message) {
    if (!_isInitialized || _isDisposed) {
      throw ModuleException(moduleId, '模块未初始化或已释放');
    }
    
    _connectionManager.sendMessage(message);
  }
  
  /// 发送模块事件
  void emitEvent(String eventType, Map<String, dynamic> data) {
    if (_eventController.isClosed) return;
    
    final event = ModuleEvent(
      moduleId: moduleId,
      eventType: eventType,
      data: data,
      timestamp: DateTime.now(),
    );
    
    _eventController.add(event);
  }
  
  /// 获取当前连接状态
  WebSocketConnectionState get connectionState =>
      _connectionManager.connectionState;
  
  /// 重新连接
  Future<void> reconnect() async {
    if (!_isInitialized || _isDisposed) {
      throw ModuleException(moduleId, '模块未初始化或已释放');
    }
    
    developer.log('重新连接模块: $moduleId', name: 'BaseModule');
    
    await _connectionManager.disconnect();
    await _connectionManager.connect();
  }
  
  /// 连接状态变化处理
  void _onConnectionStateChanged(WebSocketConnectionState state) {
    developer.log('模块连接状态变化: $moduleId -> $state', name: 'BaseModule');
    
    emitEvent('connection_state_changed', {
      'state': state.toString(),
      'connected': state == WebSocketConnectionState.connected,
    });
    
    onConnectionStateChanged(state);
  }
  
  /// 事件消息处理
  void _onEventReceived(WebSocketEvent event) {
    developer.log('模块收到事件: $moduleId -> ${event.type}', name: 'BaseModule');
    handleEvent(event);
  }
  
  // 抽象方法，由子类实现
  
  /// 模块特定的初始化逻辑
  Future<void> onInitialize();
  
  /// 模块特定的清理逻辑
  Future<void> onDispose();
  
  /// 处理请求消息
  Future<WebSocketResponse> onHandleMessage(WebSocketRequest request);
  
  /// 处理事件消息
  void onHandleEvent(WebSocketEvent event);
  
  /// 连接状态变化回调
  void onConnectionStateChanged(WebSocketConnectionState state) {
    // 默认实现为空，子类可以重写
  }
}