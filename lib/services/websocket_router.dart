import 'dart:async';
import 'dart:developer' as developer;
import '../models/websocket_models.dart';
import 'websocket_module.dart';

/// WebSocket路由分发器实现
class WebSocketRouterImpl implements WebSocketRouter {
  final Map<String, WebSocketModule> _modules = {};
  
  @override
  void registerModule(String path, WebSocketModule module) {
    _modules[path] = module;
    developer.log('模块已注册: $path -> ${module.moduleId}', name: 'WebSocketRouter');
  }
  
  @override
  void unregisterModule(String path) {
    final module = _modules.remove(path);
    if (module != null) {
      developer.log('模块已注销: $path -> ${module.moduleId}', name: 'WebSocketRouter');
    }
  }
  
  @override
  Future<void> routeMessage(String path, Map<String, dynamic> message) async {
    final module = _modules[path];
    if (module == null) {
      developer.log('未找到路径处理器: $path', name: 'WebSocketRouter');
      return;
    }
    
    try {
      final wsMessage = WebSocketMessage.fromJson(message);
      
      if (wsMessage is WebSocketRequest) {
        await module.handleMessage(wsMessage);
      } else if (wsMessage is WebSocketEvent) {
        module.handleEvent(wsMessage);
      } else {
        developer.log('不支持的消息类型: ${wsMessage.type}', name: 'WebSocketRouter');
      }
    } catch (e, stackTrace) {
      developer.log(
        '路由消息时发生错误: $e',
        name: 'WebSocketRouter',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }
  
  @override
  List<String> getRegisteredPaths() {
    return _modules.keys.toList();
  }
  
  /// 获取已注册的模块
  Map<String, WebSocketModule> getRegisteredModules() {
    return Map.from(_modules);
  }
  
  /// 根据路径获取模块
  WebSocketModule? getModuleByPath(String path) {
    return _modules[path];
  }
  
  /// 清除所有注册的模块
  void clearModules() {
    _modules.clear();
    developer.log('所有模块已清除', name: 'WebSocketRouter');
  }
}