/*
Copyright 2025 kozakemi

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

import 'package:shared_preferences/shared_preferences.dart';
import 'websocket_module.dart';

/// WebSocket配置
class WebSocketConfig {
  static const String _serverAddressKey = 'websocket_server_address';
  
  // 默认使用本地地址进行开发测试，如果需要连接到实际服务器，可以修改这些值
  static const String _defaultServerHost = 'localhost';
  static const int _defaultServerPort = 8080; // 使用不同的端口避免与Flutter开发服务器冲突
  static const String _defaultServerAddress = '$_defaultServerHost:$_defaultServerPort';

  static const Duration defaultReconnectInterval = Duration(seconds: 5);
  static const Duration defaultRequestTimeout = Duration(seconds: 10);
  static const Duration defaultHeartbeatInterval = Duration(seconds: 30);

  /// 获取服务器地址（从 SharedPreferences 或使用默认值）
  static Future<String> getServerAddress() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_serverAddressKey) ?? _defaultServerAddress;
    } catch (e) {
      return _defaultServerAddress;
    }
  }

  /// 设置服务器地址
  static Future<void> setServerAddress(String address) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_serverAddressKey, address);
    } catch (e) {
      // 忽略错误
    }
  }

  /// 获取默认服务器地址
  static String get defaultServerAddress => _defaultServerAddress;

  /// 默认服务器URL（同步版本，用于初始化时）
  static String get defaultServerUrl => 'ws://$_defaultServerHost:$_defaultServerPort';

  /// 获取服务器URL（异步版本，从 SharedPreferences 读取）
  static Future<String> getServerUrl() async {
    final address = await getServerAddress();
    return 'ws://$address';
  }

  /// 获取完整的WebSocket URL（异步版本）
  static Future<String> getWebSocketUrl(String path) async {
    final serverUrl = await getServerUrl();
    return '$serverUrl$path';
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

  /// 根据模块ID获取完整的服务器URL（同步版本，使用默认地址）
  static String getServerUrl(String moduleId) =>
      WebSocketConfig.defaultServerUrl + getPath(moduleId);

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

  /// 初始化默认配置（同步版本，使用默认地址）
  static void initializeDefaultConfigs() {
    initializeDefaultConfigsWithUrl(WebSocketConfig.defaultServerUrl);
  }

  /// 使用指定服务器URL初始化默认配置
  static void initializeDefaultConfigsWithUrl(String serverUrl) {
    // WiFi模块配置
    registerConfig(ModuleConfig(
      moduleId: 'wifi',
      websocketPath: '/wifi',
      // 使用基础服务器地址，连接管理器会追加路径
      serverUrl: serverUrl,
      reconnectInterval: const Duration(seconds: 5),
      requestTimeout: const Duration(seconds: 15), // WiFi操作可能需要更长时间
      autoStart: true, // 自动启动
    ));

    // 亮度模块配置
    registerConfig(ModuleConfig(
      moduleId: 'brightness',
      websocketPath: '/brightness',
      // 使用基础服务器地址，连接管理器会追加路径
      serverUrl: serverUrl,
      reconnectInterval: const Duration(seconds: 5),
      requestTimeout: const Duration(seconds: 10),
      autoStart: true, // 自动启动
    ));
  }

  /// 异步初始化默认配置（从 SharedPreferences 读取地址）
  static Future<void> initializeDefaultConfigsAsync() async {
    final serverUrl = await WebSocketConfig.getServerUrl();
    initializeDefaultConfigsWithUrl(serverUrl);
  }

  /// 获取所有配置
  static Map<String, ModuleConfig> getAllConfigs() => Map.from(_configs);

  /// 清除所有配置
  static void clearConfigs() {
    _configs.clear();
  }
}
