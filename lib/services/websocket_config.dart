import 'websocket_module.dart';

/// WebSocket配置
class WebSocketConfig {
  // 默认使用本地地址进行开发测试，如果需要连接到实际服务器，可以修改这些值
  static const String serverHost = '172.20.10.2';
  static const int serverPort = 8080; // 使用不同的端口避免与Flutter开发服务器冲突

  // 备用服务器配置（实际部署时使用）
  static const String productionServerHost = '172.20.10.2';
  static const int productionServerPort = 8080;

  static const Duration defaultReconnectInterval = Duration(seconds: 5);
  static const Duration defaultRequestTimeout = Duration(seconds: 10);
  static const Duration defaultHeartbeatInterval = Duration(seconds: 30);

  /// 默认服务器URL
  static String get defaultServerUrl => 'ws://$serverHost:$serverPort';

  /// 获取完整的WebSocket URL
  static String getWebSocketUrl(String path) {
    return 'ws://$serverHost:$serverPort$path';
  }

  /// 获取生产环境WebSocket URL
  static String getProductionWebSocketUrl(String path) {
    return 'ws://$productionServerHost:$productionServerPort$path';
  }
}

/// WebSocket路径注册表
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

  /// 根据模块ID获取WebSocket路径
  static String getPath(String moduleId) =>
      _pathMapping[moduleId] ?? '/unknown';

  /// 根据模块ID获取完整的服务器URL
  static String getServerUrl(String moduleId) =>
      WebSocketConfig.getWebSocketUrl(getPath(moduleId));

  /// 获取所有已注册的路径
  static Map<String, String> getAllPaths() => Map.from(_pathMapping);
}

/// 模块配置注册表
class ModuleConfigRegistry {
  static final Map<String, ModuleConfig> _configs = {};

  /// 注册模块配置
  static void registerConfig(ModuleConfig config) {
    _configs[config.moduleId] = config;
  }

  /// 获取模块配置
  static ModuleConfig? getConfig(String moduleId) {
    return _configs[moduleId];
  }

  /// 获取模块配置，如果不存在则创建默认配置
  static ModuleConfig getConfigOrDefault(String moduleId) {
    return _configs[moduleId] ?? _createDefaultConfig(moduleId);
  }

  /// 创建默认配置
  static ModuleConfig _createDefaultConfig(String moduleId) {
    // 使用基础服务器地址，路径由连接管理器单独拼接
    final path = WebSocketPathRegistry.getPath(moduleId);
    final serverUrl = WebSocketConfig.defaultServerUrl;

    return ModuleConfig(
      moduleId: moduleId,
      websocketPath: path,
      serverUrl: serverUrl,
      reconnectInterval: WebSocketConfig.defaultReconnectInterval,
      requestTimeout: WebSocketConfig.defaultRequestTimeout,
      autoStart: true,
    );
  }

  /// 初始化默认配置
  static void initializeDefaultConfigs() {
    // WiFi模块配置
    registerConfig(ModuleConfig(
      moduleId: 'wifi',
      websocketPath: '/wifi',
      // 使用基础服务器地址，连接管理器会追加路径
      serverUrl: WebSocketConfig.defaultServerUrl,
      reconnectInterval: const Duration(seconds: 5),
      requestTimeout: const Duration(seconds: 15), // WiFi操作可能需要更长时间
      autoStart: true, // 自动启动
    ));

    // 亮度模块配置
    registerConfig(ModuleConfig(
      moduleId: 'brightness',
      websocketPath: '/brightness',
      // 使用基础服务器地址，连接管理器会追加路径
      serverUrl: WebSocketConfig.defaultServerUrl,
      reconnectInterval: const Duration(seconds: 5),
      requestTimeout: const Duration(seconds: 10),
      autoStart: true, // 自动启动
    ));
  }

  /// 获取所有配置
  static Map<String, ModuleConfig> getAllConfigs() => Map.from(_configs);

  /// 清除所有配置
  static void clearConfigs() {
    _configs.clear();
  }
}
