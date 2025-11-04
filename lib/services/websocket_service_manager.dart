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

import 'dart:async';
import 'dart:developer' as developer;

import 'websocket_module_manager.dart';
import 'websocket_router.dart';
import 'wifi_module.dart';
import 'brightness_module.dart';
import 'websocket_config.dart';

/// WebSocket服务管理器
/// 提供全局单例访问各个模块
class WebSocketServiceManager {
  static WebSocketServiceManager? _instance;
  static WebSocketServiceManager get instance {
    _instance ??= WebSocketServiceManager._();
    return _instance!;
  }

  WebSocketServiceManager._();

  late final WebSocketModuleManagerImpl _moduleManager;
  WiFiModule? _wifiModule;
  BrightnessModule? _brightnessModule;

  bool _initialized = false;

  /// 初始化服务管理器
  Future<void> initialize() async {
    if (_initialized) return;

    try {
      developer.log('初始化WebSocket服务管理器', name: 'ServiceManager');
      // 注册默认模块配置，确保URL与路径配置正确
      ModuleConfigRegistry.initializeDefaultConfigs();
      
      final router = WebSocketRouterImpl();
      _moduleManager = WebSocketModuleManagerImpl(router);
      await _moduleManager.initializeModules();
      
      // 启动所有模块（允许部分失败）
      try {
        await _moduleManager.startAllModules();
        developer.log('所有WebSocket模块启动成功', name: 'ServiceManager');
      } catch (e) {
        developer.log('部分WebSocket模块启动失败，但服务管理器将继续运行: $e', name: 'ServiceManager');
      }
      
      // 获取模块实例
      _wifiModule = _moduleManager.getModule('wifi') as WiFiModule?;
      _brightnessModule = _moduleManager.getModule('brightness') as BrightnessModule?;
      
      _initialized = true;
      developer.log('WebSocket服务管理器初始化完成', name: 'ServiceManager');
    } catch (e, stackTrace) {
      developer.log(
        'WebSocket服务管理器初始化失败: $e',
        name: 'ServiceManager',
        error: e,
        stackTrace: stackTrace,
      );
      
      // 标记为已初始化，但处于错误状态，避免重复初始化
      _initialized = true;
      
      // 不重新抛出异常，允许应用继续运行
      developer.log('WebSocket服务将在离线模式下运行', name: 'ServiceManager');
    }
  }

  /// 获取WiFi模块
  WiFiModule? get wifiModule {
    if (!_initialized) {
      developer.log('服务管理器未初始化，无法获取WiFi模块', name: 'ServiceManager');
      return null;
    }
    return _wifiModule;
  }

  /// 获取亮度模块
  BrightnessModule? get brightnessModule {
    if (!_initialized) {
      developer.log('服务管理器未初始化，无法获取亮度模块', name: 'ServiceManager');
      return null;
    }
    return _brightnessModule;
  }

  /// 获取模块管理器
  WebSocketModuleManagerImpl get moduleManager => _moduleManager;

  /// 检查是否已初始化
  bool get isInitialized => _initialized;

  /// 停止所有服务
  Future<void> dispose() async {
    if (!_initialized) return;

    try {
      developer.log('停止WebSocket服务管理器', name: 'ServiceManager');
      
      await _moduleManager.stopAllModules();
      
      _wifiModule = null;
      _brightnessModule = null;
      _initialized = false;
      
      developer.log('WebSocket服务管理器已停止', name: 'ServiceManager');
    } catch (e, stackTrace) {
      developer.log(
        '停止WebSocket服务管理器失败: $e',
        name: 'ServiceManager',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// 重启所有服务
  Future<void> restart() async {
    developer.log('重启WebSocket服务管理器', name: 'ServiceManager');
    await dispose();
    await initialize();
  }

  /// 获取所有模块的健康状态
  Map<String, bool> getModulesHealthStatus() {
    if (!_initialized) return {};
    return _moduleManager.getModulesHealthStatus();
  }
}