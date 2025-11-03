# WebSocket 架构重构设计文档

## 1. 架构设计原则

### 1.1 模块解耦原则
- **完全独立**：WiFi控制模块与亮度控制模块完全解耦，互不依赖
- **接口隔离**：每个模块通过标准化接口与核心系统交互
- **单一职责**：每个模块只负责自己领域的功能实现
- **依赖倒置**：模块依赖抽象接口，而非具体实现

### 1.2 可扩展性原则
- **插件化设计**：新模块可以通过插件方式动态注册
- **路由可配置**：WebSocket路径通过配置文件或注册机制管理
- **向后兼容**：新增功能不影响现有模块的稳定性
- **热插拔支持**：支持模块的动态加载和卸载

## 2. 核心组件设计

### 2.1 WebSocket路由分发器 (WebSocketRouter)
```dart
abstract class WebSocketRouter {
  // 注册模块处理器
  void registerModule(String path, WebSocketModule module);
  
  // 注销模块处理器
  void unregisterModule(String path);
  
  // 路由消息到对应模块
  Future<void> routeMessage(String path, Map<String, dynamic> message);
  
  // 获取所有注册的路径
  List<String> getRegisteredPaths();
}
```

### 2.2 模块管理器 (WebSocketModuleManager)
```dart
abstract class WebSocketModuleManager {
  // 初始化所有模块
  Future<void> initializeModules();
  
  // 启动指定模块
  Future<void> startModule(String moduleId);
  
  // 停止指定模块
  Future<void> stopModule(String moduleId);
  
  // 获取模块状态
  ModuleStatus getModuleStatus(String moduleId);
  
  // 模块健康检查
  Future<bool> healthCheck(String moduleId);
}
```

### 2.3 WebSocket模块接口 (WebSocketModule)
```dart
abstract class WebSocketModule {
  String get moduleId;
  String get websocketPath;
  
  // 模块初始化
  Future<void> initialize();
  
  // 处理WebSocket消息
  Future<WebSocketResponse> handleMessage(WebSocketRequest request);
  
  // 处理WebSocket事件
  void handleEvent(WebSocketEvent event);
  
  // 模块清理
  Future<void> dispose();
  
  // 连接状态流
  Stream<WebSocketConnectionState> get connectionStateStream;
  
  // 模块事件流
  Stream<ModuleEvent> get eventStream;
}
```

## 3. 模块化实现方案

### 3.1 WiFi控制模块 (WiFiModule)
**路径**: `/wifi`
**服务器地址**: `ws://172.20.10.2:8080/wifi`

**核心功能**:
- WiFi开关控制 (`wifi_enable_request`)
- 网络状态查询 (`wifi_status_request`)
- 网络扫描 (`wifi_scan_request`)
- 网络连接 (`wifi_connect_request`)
- 网络断开 (`wifi_disconnect_request`)

**错误处理**:
```dart
enum WiFiError {
  ok(0, '成功'),
  unknown(-1, '未知错误'),
  badRequest(1, '请求数据错误'),
  notSupported(2, '操作不支持'),
  wifiDisabled(3, 'WiFi已关闭'),
  alreadyConnected(4, '已连接同一SSID'),
  networkNotFound(5, '扫描无该SSID'),
  authFailed(6, '认证失败/密码错误'),
  timeout(7, '连接/操作超时'),
  internal(8, '后端内部错误'),
  // ... 其他错误码
}
```

### 3.2 亮度控制模块 (BrightnessModule)
**路径**: `/brightness`
**服务器地址**: `ws://172.20.10.2:8080/brightness`

**核心功能**:
- 亮度状态查询 (`brightness_status_request`)
- 亮度设置 (`brightness_set_request`)
- 自动亮度控制 (`brightness_auto_request`)

**错误处理**:
```dart
enum BrightnessError {
  ok(0, '成功'),
  unknown(-1, '未知错误'),
  badRequest(1, '数据缺失/类型不符'),
  invalidValue(2, '亮度值无效'),
  notSupported(3, '设备不支持亮度调节'),
  permission(4, '权限不足'),
  deviceError(5, '硬件设备错误'),
  internal(6, '后端内部错误'),
}
```

## 4. WebSocket路径规划

### 4.1 路径注册机制
```dart
class WebSocketPathRegistry {
  static const Map<String, String> _pathMapping = {
    'wifi': '/wifi',
    'brightness': '/brightness',
    // 预留扩展路径
    'bluetooth': '/bluetooth',
    'audio': '/audio',
    'network': '/network',
    'system': '/system',
  };
  
  static String getPath(String moduleId) => _pathMapping[moduleId] ?? '/unknown';
  static String getServerUrl(String moduleId) => 'ws://172.20.10.2:8080${getPath(moduleId)}';
}
```

### 4.2 路由分发逻辑
```dart
class WebSocketRouterImpl implements WebSocketRouter {
  final Map<String, WebSocketModule> _modules = {};
  
  @override
  void registerModule(String path, WebSocketModule module) {
    _modules[path] = module;
    print('模块已注册: $path -> ${module.moduleId}');
  }
  
  @override
  Future<void> routeMessage(String path, Map<String, dynamic> message) async {
    final module = _modules[path];
    if (module != null) {
      final request = WebSocketRequest.fromJson(message);
      await module.handleMessage(request);
    } else {
      print('未找到路径处理器: $path');
    }
  }
}
```

## 5. 扩展性考虑

### 5.1 新模块接入流程
1. **实现WebSocketModule接口**
2. **定义模块专用的消息类型和错误码**
3. **在WebSocketPathRegistry中注册路径**
4. **在ModuleManager中注册模块**
5. **编写模块测试用例**

### 5.2 模块配置管理
```dart
class ModuleConfig {
  final String moduleId;
  final String websocketPath;
  final String serverUrl;
  final Duration reconnectInterval;
  final Duration requestTimeout;
  final bool autoStart;
  
  const ModuleConfig({
    required this.moduleId,
    required this.websocketPath,
    required this.serverUrl,
    this.reconnectInterval = const Duration(seconds: 5),
    this.requestTimeout = const Duration(seconds: 10),
    this.autoStart = true,
  });
}
```

### 5.3 模块生命周期管理
```dart
enum ModuleStatus {
  uninitialized,
  initializing,
  running,
  stopping,
  stopped,
  error,
}

class ModuleLifecycle {
  ModuleStatus _status = ModuleStatus.uninitialized;
  
  Future<void> start() async {
    _status = ModuleStatus.initializing;
    try {
      await _initialize();
      _status = ModuleStatus.running;
    } catch (e) {
      _status = ModuleStatus.error;
      rethrow;
    }
  }
  
  Future<void> stop() async {
    _status = ModuleStatus.stopping;
    await _cleanup();
    _status = ModuleStatus.stopped;
  }
}
```

## 6. 实现步骤规划

### 阶段1: 核心架构搭建 (1-2天)
1. **创建基础接口定义**
   - WebSocketModule接口
   - WebSocketRouter接口
   - WebSocketModuleManager接口

2. **实现核心组件**
   - WebSocketRouterImpl
   - WebSocketModuleManagerImpl
   - 通用WebSocketClient

3. **创建消息模型**
   - 统一的WebSocketMessage基类
   - WebSocketRequest/Response/Event类

### 阶段2: WiFi模块重构 (2-3天)
1. **移除旧的WiFi WebSocket实现**
2. **创建新的WiFiModule类**
3. **实现WiFi相关的消息处理逻辑**
4. **更新WiFi页面以使用新架构**
5. **编写WiFi模块测试用例**

### 阶段3: 亮度模块重构 (2-3天)
1. **移除旧的亮度WebSocket实现**
2. **创建新的BrightnessModule类**
3. **实现亮度相关的消息处理逻辑**
4. **更新显示设置页面以使用新架构**
5. **编写亮度模块测试用例**

### 阶段4: 集成测试与优化 (1-2天)
1. **模块间集成测试**
2. **性能优化和内存泄漏检查**
3. **错误处理和异常恢复测试**
4. **文档更新和代码审查**

## 7. 技术实现细节

### 7.1 消息序列化
```dart
abstract class WebSocketMessage {
  final String type;
  final String? requestId;
  
  const WebSocketMessage({required this.type, this.requestId});
  
  Map<String, dynamic> toJson();
  
  static WebSocketMessage fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String;
    
    if (type.endsWith('_request')) {
      return WebSocketRequest.fromJson(json);
    } else if (type.endsWith('_response')) {
      return WebSocketResponse.fromJson(json);
    } else if (type.endsWith('_event')) {
      return WebSocketEvent.fromJson(json);
    }
    
    throw ArgumentError('Unknown message type: $type');
  }
}
```

### 7.2 连接管理
```dart
class WebSocketConnectionManager {
  final Map<String, WebSocketClient> _connections = {};
  
  Future<WebSocketClient> getConnection(String path) async {
    if (!_connections.containsKey(path)) {
      final config = ModuleConfigRegistry.getConfig(path);
      final client = WebSocketClient(
        url: config.serverUrl,
        reconnectInterval: config.reconnectInterval,
        requestTimeout: config.requestTimeout,
      );
      
      await client.connect();
      _connections[path] = client;
    }
    
    return _connections[path]!;
  }
  
  Future<void> closeConnection(String path) async {
    final client = _connections.remove(path);
    await client?.disconnect();
  }
}
```

### 7.3 错误处理策略
```dart
class ModuleErrorHandler {
  static Future<T> handleModuleOperation<T>(
    String moduleId,
    Future<T> Function() operation,
  ) async {
    try {
      return await operation();
    } on WebSocketException catch (e) {
      print('WebSocket错误 [$moduleId]: ${e.message}');
      rethrow;
    } on TimeoutException catch (e) {
      print('操作超时 [$moduleId]: ${e.message}');
      rethrow;
    } catch (e) {
      print('未知错误 [$moduleId]: $e');
      rethrow;
    }
  }
}
```

## 8. 测试策略

### 8.1 单元测试
- 每个模块的独立功能测试
- 消息序列化/反序列化测试
- 错误处理逻辑测试

### 8.2 集成测试
- 模块间通信测试
- WebSocket连接稳定性测试
- 并发操作测试

### 8.3 端到端测试
- 完整用户操作流程测试
- 网络异常恢复测试
- 性能压力测试

## 9. 部署和监控

### 9.1 配置管理
```dart
class WebSocketConfig {
  static const String serverHost = '172.20.10.2';
  static const int serverPort = 8080;
  
  static const Duration defaultReconnectInterval = Duration(seconds: 5);
  static const Duration defaultRequestTimeout = Duration(seconds: 10);
  static const Duration defaultHeartbeatInterval = Duration(seconds: 30);
}
```

### 9.2 日志和监控
```dart
class ModuleLogger {
  static void logModuleEvent(String moduleId, String event, [Map<String, dynamic>? data]) {
    final timestamp = DateTime.now().toIso8601String();
    print('[$timestamp] [$moduleId] $event ${data != null ? jsonEncode(data) : ''}');
  }
  
  static void logError(String moduleId, String error, [StackTrace? stackTrace]) {
    final timestamp = DateTime.now().toIso8601String();
    print('[$timestamp] [ERROR] [$moduleId] $error');
    if (stackTrace != null) {
      print(stackTrace);
    }
  }
}
```

这个架构设计确保了：
- **完全解耦**：WiFi和亮度模块完全独立
- **高度可扩展**：新模块可以轻松接入
- **稳定可靠**：完善的错误处理和恢复机制
- **易于维护**：清晰的模块边界和接口定义
- **测试友好**：每个组件都可以独立测试