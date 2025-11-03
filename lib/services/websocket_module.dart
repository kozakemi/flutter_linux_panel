import 'dart:async';
import '../models/websocket_models.dart';

/// WebSocket模块接口
abstract class WebSocketModule {
  /// 模块唯一标识
  String get moduleId;
  
  /// WebSocket路径
  String get websocketPath;
  
  /// 模块初始化
  Future<void> initialize();
  
  /// 处理WebSocket消息
  Future<WebSocketResponse> handleMessage(WebSocketRequest request);
  
  /// 处理WebSocket事件
  void handleEvent(WebSocketEvent event);
  
  /// 模块清理
  Future<void> dispose();
  
  /// 连接状态流
  Stream<WebSocketConnectionState> get connectionStateStream;
  
  /// 模块事件流
  Stream<ModuleEvent> get eventStream;
  
  /// 获取模块状态
  ModuleStatus get status;
}

/// WebSocket路由分发器接口
abstract class WebSocketRouter {
  /// 注册模块处理器
  void registerModule(String path, WebSocketModule module);
  
  /// 注销模块处理器
  void unregisterModule(String path);
  
  /// 路由消息到对应模块
  Future<void> routeMessage(String path, Map<String, dynamic> message);
  
  /// 获取所有注册的路径
  List<String> getRegisteredPaths();
}

/// WebSocket模块管理器接口
abstract class WebSocketModuleManager {
  /// 初始化所有模块
  Future<void> initializeModules();
  
  /// 启动指定模块
  Future<void> startModule(String moduleId);
  
  /// 停止指定模块
  Future<void> stopModule(String moduleId);
  
  /// 获取模块状态
  ModuleStatus getModuleStatus(String moduleId);
  
  /// 模块健康检查
  Future<bool> healthCheck(String moduleId);
  
  /// 获取所有模块
  List<WebSocketModule> getAllModules();
  
  /// 根据ID获取模块
  WebSocketModule? getModule(String moduleId);
}

/// 模块配置
class ModuleConfig {
  final String moduleId;
  final String websocketPath;
  final String serverUrl;
  final Duration reconnectInterval;
  final Duration requestTimeout;
  final Duration heartbeatInterval;
  final int maxReconnectAttempts;
  final bool autoStart;

  const ModuleConfig({
    required this.moduleId,
    required this.websocketPath,
    required this.serverUrl,
    this.reconnectInterval = const Duration(seconds: 5),
    this.requestTimeout = const Duration(seconds: 10),
    this.heartbeatInterval = const Duration(seconds: 30),
    this.maxReconnectAttempts = 5,
    this.autoStart = true,
  });

  @override
  String toString() => 'ModuleConfig(moduleId: $moduleId, websocketPath: $websocketPath, serverUrl: $serverUrl)';
}