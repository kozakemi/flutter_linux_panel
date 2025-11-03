import 'dart:async';
import 'dart:developer' as developer;

import '../models/websocket_models.dart';
import 'websocket_module.dart';
import 'websocket_router.dart';
import 'websocket_config.dart';
import 'wifi_module.dart';
import 'brightness_module.dart';

/// WebSocket模块管理器实现
class WebSocketModuleManagerImpl implements WebSocketModuleManager {
  final WebSocketRouterImpl _router;
  final Map<String, WebSocketModule> _modules = {};
  final Map<String, ModuleStatus> _moduleStatus = {};
  
  WebSocketModuleManagerImpl(this._router);
  
  @override
  Future<void> initializeModules() async {
    developer.log('开始初始化所有模块', name: 'ModuleManager');
    
    final configs = ModuleConfigRegistry.getAllConfigs();
    for (final config in configs.values) {
      if (config.autoStart) {
        try {
          await startModule(config.moduleId);
        } catch (e) {
          developer.log(
            '自动启动模块失败: ${config.moduleId}, 错误: $e',
            name: 'ModuleManager',
          );
        }
      }
    }
    
    developer.log('模块初始化完成', name: 'ModuleManager');
  }
  
  @override
  Future<void> startModule(String moduleId) async {
    if (_modules.containsKey(moduleId)) {
      developer.log('模块已存在: $moduleId', name: 'ModuleManager');
      return;
    }
    
    _moduleStatus[moduleId] = ModuleStatus.initializing;
    
    try {
      final module = await _createModule(moduleId);
      if (module == null) {
        throw ModuleException(moduleId, '无法创建模块');
      }
      
      await module.initialize();
      
      _modules[moduleId] = module;
      _router.registerModule(module.websocketPath, module);
      _moduleStatus[moduleId] = ModuleStatus.running;
      
      developer.log('模块启动成功: $moduleId', name: 'ModuleManager');
    } catch (e, stackTrace) {
      _moduleStatus[moduleId] = ModuleStatus.error;
      developer.log(
        '模块启动失败: $moduleId, 错误: $e',
        name: 'ModuleManager',
        error: e,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }
  
  @override
  Future<void> stopModule(String moduleId) async {
    final module = _modules[moduleId];
    if (module == null) {
      developer.log('模块不存在: $moduleId', name: 'ModuleManager');
      return;
    }
    
    _moduleStatus[moduleId] = ModuleStatus.stopping;
    
    try {
      _router.unregisterModule(module.websocketPath);
      await module.dispose();
      
      _modules.remove(moduleId);
      _moduleStatus[moduleId] = ModuleStatus.stopped;
      
      developer.log('模块停止成功: $moduleId', name: 'ModuleManager');
    } catch (e, stackTrace) {
      _moduleStatus[moduleId] = ModuleStatus.error;
      developer.log(
        '模块停止失败: $moduleId, 错误: $e',
        name: 'ModuleManager',
        error: e,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }
  
  @override
  ModuleStatus getModuleStatus(String moduleId) {
    return _moduleStatus[moduleId] ?? ModuleStatus.uninitialized;
  }
  
  @override
  Future<bool> healthCheck(String moduleId) async {
    final module = _modules[moduleId];
    if (module == null) {
      return false;
    }
    
    try {
      // 检查模块状态
      final status = getModuleStatus(moduleId);
      if (status != ModuleStatus.running) {
        return false;
      }
      
      // 检查连接状态
      final connectionState = await module.connectionStateStream.first
          .timeout(const Duration(seconds: 5));
      
      return connectionState == WebSocketConnectionState.connected;
    } catch (e) {
      developer.log('健康检查失败: $moduleId, 错误: $e', name: 'ModuleManager');
      return false;
    }
  }
  
  @override
  List<WebSocketModule> getAllModules() {
    return _modules.values.toList();
  }
  
  @override
  WebSocketModule? getModule(String moduleId) {
    return _modules[moduleId];
  }
  
  /// 创建模块实例
  Future<WebSocketModule?> _createModule(String moduleId) async {
    developer.log('创建模块: $moduleId', name: 'ModuleManager');
    
    switch (moduleId) {
      case 'wifi':
        // 动态导入WiFi模块
        final wifiModule = await _createWiFiModule();
        return wifiModule;
      case 'brightness':
        // 动态导入亮度模块
        final brightnessModule = await _createBrightnessModule();
        return brightnessModule;
      default:
        developer.log('未知模块类型: $moduleId', name: 'ModuleManager');
        return null;
    }
  }
  
  /// 创建WiFi模块
  Future<WebSocketModule?> _createWiFiModule() async {
    try {
      // 延迟导入WiFi模块以避免循环依赖
      final module = await _loadWiFiModule();
      return module;
    } catch (e, stackTrace) {
      developer.log(
        '创建WiFi模块失败: $e',
        name: 'ModuleManager',
        error: e,
        stackTrace: stackTrace,
      );
      return null;
    }
  }
  
  /// 创建亮度模块
  Future<WebSocketModule?> _createBrightnessModule() async {
    try {
      // 延迟导入亮度模块以避免循环依赖
      final module = await _loadBrightnessModule();
      return module;
    } catch (e, stackTrace) {
      developer.log(
        '创建亮度模块失败: $e',
        name: 'ModuleManager',
        error: e,
        stackTrace: stackTrace,
      );
      return null;
    }
  }
  
  /// 加载WiFi模块
  Future<WebSocketModule> _loadWiFiModule() async {
    return WiFiModule();
  }
  
  /// 加载亮度模块
  Future<WebSocketModule> _loadBrightnessModule() async {
    return BrightnessModule();
  }
  
  /// 启动所有模块
  Future<void> startAllModules() async {
    developer.log('启动所有模块', name: 'ModuleManager');
    
    // 启动WiFi模块
    try {
      await startModule('wifi');
    } catch (e) {
      developer.log('启动WiFi模块失败: $e', name: 'ModuleManager');
    }
    
    // 启动亮度模块
    try {
      await startModule('brightness');
    } catch (e) {
      developer.log('启动亮度模块失败: $e', name: 'ModuleManager');
    }
  }

  /// 停止所有模块
  Future<void> stopAllModules() async {
    developer.log('停止所有模块', name: 'ModuleManager');
    
    final moduleIds = _modules.keys.toList();
    for (final moduleId in moduleIds) {
      try {
        await stopModule(moduleId);
      } catch (e) {
        developer.log('停止模块失败: $moduleId, 错误: $e', name: 'ModuleManager');
      }
    }
  }
  
  /// 重启模块
  Future<void> restartModule(String moduleId) async {
    developer.log('重启模块: $moduleId', name: 'ModuleManager');
    
    await stopModule(moduleId);
    await startModule(moduleId);
  }
  
  /// 获取所有模块的健康状态
  Map<String, bool> getModulesHealthStatus() {
    final healthStatus = <String, bool>{};
    
    for (final moduleId in _modules.keys) {
      final status = getModuleStatus(moduleId);
      healthStatus[moduleId] = status == ModuleStatus.running;
    }
    
    return healthStatus;
  }

  /// 获取模块统计信息
  Map<String, dynamic> getModuleStats() {
    final stats = <String, dynamic>{};
    
    for (final entry in _moduleStatus.entries) {
      stats[entry.key] = {
        'status': entry.value.toString(),
        'running': entry.value == ModuleStatus.running,
      };
    }
    
    return {
      'total_modules': _moduleStatus.length,
      'running_modules': _moduleStatus.values.where((s) => s == ModuleStatus.running).length,
      'modules': stats,
    };
  }
}