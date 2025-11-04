import 'dart:async';
import 'dart:developer' as developer;
import '../models/websocket_models.dart';
import '../models/brightness_models.dart';
import 'websocket_base_module.dart';

/// 亮度控制 WebSocket模块实现
class BrightnessModule extends WebSocketBaseModule {
  static const String _moduleId = 'brightness';
  static const String _websocketPath = '/brightness';
  
  // 状态管理
  BrightnessStatus? _currentStatus;
  bool _isAdjusting = false;
  
  // 状态流控制器
  final StreamController<BrightnessStatus> _statusController = 
      StreamController<BrightnessStatus>.broadcast();
  final StreamController<bool> _adjustingController = 
      StreamController<bool>.broadcast();
  final StreamController<BrightnessChangeEvent> _changeEventController = 
      StreamController<BrightnessChangeEvent>.broadcast();
  
  @override
  String get moduleId => _moduleId;
  
  @override
  String get websocketPath => _websocketPath;
  
  /// 亮度状态流
  Stream<BrightnessStatus> get statusStream => _statusController.stream;
  
  /// 调节状态流
  Stream<bool> get adjustingStream => _adjustingController.stream;
  
  /// 亮度变化事件流
  Stream<BrightnessChangeEvent> get changeEventStream => _changeEventController.stream;
  
  /// 当前亮度状态
  BrightnessStatus? get currentStatus => _currentStatus;
  
  /// 是否正在调节亮度
  bool get isAdjusting => _isAdjusting;
  
  @override
  ModuleStatus get status {
    if (connectionState == WebSocketConnectionState.connected) {
      return ModuleStatus.running;
    } else if (connectionState == WebSocketConnectionState.connecting) {
      return ModuleStatus.initializing;
    } else if (connectionState == WebSocketConnectionState.disconnected) {
      return ModuleStatus.stopped;
    } else {
      return ModuleStatus.error;
    }
  }
  
  @override
  Future<void> onInitialize() async {
    developer.log('亮度模块初始化', name: 'BrightnessModule');
    
    // 初始化状态
    _currentStatus = null;
    _isAdjusting = false;
  }
  
  @override
  Future<void> onDispose() async {
    developer.log('亮度模块释放', name: 'BrightnessModule');
    
    // 关闭所有流控制器
    await _statusController.close();
    await _adjustingController.close();
    await _changeEventController.close();
  }
  
  @override
  Future<WebSocketResponse> onHandleMessage(WebSocketRequest request) async {
    // 亮度模块通常不需要处理来自服务器的请求消息
    // 这里可以根据需要添加处理逻辑
    developer.log('亮度模块收到请求消息: ${request.type}', name: 'BrightnessModule');
    
    // 返回一个默认的成功响应，类型按 BrightnessResponseTypes 与请求类型成对映射
    String responseType;
    switch (request.type) {
      case BrightnessRequestTypes.getStatus:
        responseType = BrightnessResponseTypes.status;
        break;
      case BrightnessRequestTypes.setBrightness:
        responseType = BrightnessResponseTypes.set;
        break;
      case BrightnessRequestTypes.setAuto:
        responseType = BrightnessResponseTypes.auto;
        break;
      default:
        responseType = request.type; // 未识别类型，沿用原类型
    }
    return WebSocketResponse(
      type: responseType,
      requestId: request.requestId!,
      success: true,
      errorCode: 0,
      data: {},
    );
  }
  
  @override
  void onHandleEvent(WebSocketEvent event) {
    developer.log('亮度模块收到事件: ${event.type}', name: 'BrightnessModule');
    
    try {
      switch (event.type) {
        case BrightnessEventTypes.brightnessChanged:
          _handleBrightnessChangedEvent(event);
          break;
        case BrightnessEventTypes.autoModeChanged:
          _handleAutoModeChangedEvent(event);
          break;
        default:
          developer.log('未知亮度事件类型: ${event.type}', name: 'BrightnessModule');
      }
    } catch (e, stackTrace) {
      developer.log(
        '处理亮度事件失败: ${event.type}, 错误: $e',
        name: 'BrightnessModule',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }
  
  @override
  void onConnectionStateChanged(WebSocketConnectionState state) {
    super.onConnectionStateChanged(state);
    
    if (state == WebSocketConnectionState.connected) {
      // 连接成功后立即获取亮度状态
      getStatus().catchError((e) {
        developer.log('获取亮度状态失败: $e', name: 'BrightnessModule');
        return null;
      });
    }
  }
  
  /// 获取亮度状态
  Future<BrightnessStatus?> getStatus() async {
    try {
      developer.log('获取亮度状态', name: 'BrightnessModule');
      
      final request = BrightnessRequestBuilder.createGetStatusRequest();
      final response = await sendRequest(request);
      
      final status = BrightnessResponseParser.parseStatusResponse(response);
      if (status != null) {
        _updateStatus(status);
        return status;
      }

      final error = BrightnessResponseParser.parseError(response);
      developer.log('获取亮度状态失败: ${error.message}', name: 'BrightnessModule');
      
      return null;
    } catch (e, stackTrace) {
      developer.log(
        '获取亮度状态异常: $e',
        name: 'BrightnessModule',
        error: e,
        stackTrace: stackTrace,
      );
      return null;
    }
  }
  
  /// 设置亮度
  Future<bool> setBrightness(int brightness) async {
    if (_isAdjusting) {
      developer.log('亮度调节已在进行中', name: 'BrightnessModule');
      return false;
    }
    
    // 验证亮度值范围
    if (brightness < 0 || brightness > 100) {
      developer.log('无效的亮度值: $brightness', name: 'BrightnessModule');
      return false;
    }
    
    try {
      developer.log('设置亮度: $brightness%', name: 'BrightnessModule');
      
      _updateAdjustingState(true);
      
      final request = BrightnessRequestBuilder.createSetBrightnessRequest(
        brightness: brightness,
      );
      final response = await sendRequest(request);
      
      final ok = BrightnessResponseParser.parseSetResponse(response);
      if (ok == true) {
        await getStatus();
        return true;
      }

      final error = BrightnessResponseParser.parseError(response);
      developer.log('设置亮度失败: ${error.message}', name: 'BrightnessModule');
      return false;
    } catch (e, stackTrace) {
      developer.log(
        '设置亮度异常: $e',
        name: 'BrightnessModule',
        error: e,
        stackTrace: stackTrace,
      );
      return false;
    } finally {
      _updateAdjustingState(false);
    }
  }
  
  /// 设置自动亮度
  Future<bool> setAutoMode(bool enabled) async {
    try {
      developer.log('设置自动亮度: $enabled', name: 'BrightnessModule');
      
      final request = BrightnessRequestBuilder.createSetAutoRequest(
        enabled: enabled,
      );
      final response = await sendRequest(request);
      
      final srvAuto = BrightnessResponseParser.parseAutoResponse(response);
      if (srvAuto != null) {
        await getStatus();
        return true;
      }

      final error = BrightnessResponseParser.parseError(response);
      developer.log('设置自动亮度失败: ${error.message}', name: 'BrightnessModule');
      return false;
    } catch (e, stackTrace) {
      developer.log(
        '设置自动亮度异常: $e',
        name: 'BrightnessModule',
        error: e,
        stackTrace: stackTrace,
      );
      return false;
    }
  }
  
  /// 增加亮度
  Future<bool> increaseBrightness([int step = 10]) async {
    final currentBrightness = _currentStatus?.percentage ?? 0;
    final newBrightness = (currentBrightness + step).clamp(0, 100);
    
    if (newBrightness == currentBrightness) {
      developer.log('亮度已达到最大值', name: 'BrightnessModule');
      return false;
    }
    
    return await setBrightness(newBrightness);
  }
  
  /// 减少亮度
  Future<bool> decreaseBrightness([int step = 10]) async {
    final currentBrightness = _currentStatus?.percentage ?? 0;
    final newBrightness = (currentBrightness - step).clamp(0, 100);
    
    if (newBrightness == currentBrightness) {
      developer.log('亮度已达到最小值', name: 'BrightnessModule');
      return false;
    }
    
    return await setBrightness(newBrightness);
  }
  
  /// 切换自动亮度模式
  Future<bool> toggleAutoMode() async {
    final currentAutoMode = _currentStatus?.autoEnabled ?? false;
    return await setAutoMode(!currentAutoMode);
  }
  
  /// 处理亮度变化事件
  void _handleBrightnessChangedEvent(WebSocketEvent event) {
    try {
      final changeEvent = BrightnessChangeEvent.fromJson(event.data);
      _emitChangeEvent(changeEvent);
      
      developer.log(
        '亮度变化: ${changeEvent.oldValue}% -> ${changeEvent.newValue}%',
        name: 'BrightnessModule',
      );
      
      // 刷新状态
      getStatus().catchError((e) {
        developer.log('刷新亮度状态失败: $e', name: 'BrightnessModule');
        return null;
      });
    } catch (e) {
      developer.log('解析亮度变化事件失败: $e', name: 'BrightnessModule');
    }
  }
  
  /// 处理自动模式变化事件
  void _handleAutoModeChangedEvent(WebSocketEvent event) {
    try {
      final enabled = event.data['enabled'] as bool? ?? false;
      
      developer.log('自动亮度模式变化: $enabled', name: 'BrightnessModule');
      
      // 刷新状态
      getStatus().catchError((e) {
        developer.log('刷新亮度状态失败: $e', name: 'BrightnessModule');
        return null;
      });
    } catch (e) {
      developer.log('解析自动模式事件失败: $e', name: 'BrightnessModule');
    }
  }
  
  /// 更新亮度状态
  void _updateStatus(BrightnessStatus status) {
    _currentStatus = status;
    if (!_statusController.isClosed) {
      _statusController.add(status);
    }
    
    // 发送模块事件
    emitEvent('status_updated', status.toJson());
  }
  
  /// 更新调节状态
  void _updateAdjustingState(bool adjusting) {
    _isAdjusting = adjusting;
    if (!_adjustingController.isClosed) {
      _adjustingController.add(adjusting);
    }
    
    // 发送模块事件
    emitEvent('adjusting_state_changed', {'adjusting': adjusting});
  }
  
  /// 发送亮度变化事件
  void _emitChangeEvent(BrightnessChangeEvent changeEvent) {
    if (!_changeEventController.isClosed) {
      _changeEventController.add(changeEvent);
    }
    
    // 发送模块事件
    emitEvent('brightness_changed', changeEvent.toJson());
  }
  
  /// 获取亮度级别描述
  String getBrightnessLevelDescription(int brightness) {
    if (brightness >= 80) return '很亮';
    if (brightness >= 60) return '较亮';
    if (brightness >= 40) return '适中';
    if (brightness >= 20) return '较暗';
    return '很暗';
  }
  
  /// 获取推荐的亮度值（基于时间）
  int getRecommendedBrightness() {
    final now = DateTime.now();
    final hour = now.hour;
    
    // 根据时间推荐亮度
    if (hour >= 6 && hour < 9) {
      // 早晨：中等亮度
      return 60;
    } else if (hour >= 9 && hour < 18) {
      // 白天：较高亮度
      return 80;
    } else if (hour >= 18 && hour < 22) {
      // 傍晚：中等亮度
      return 50;
    } else {
      // 夜晚：较低亮度
      return 30;
    }
  }
  
  /// 应用推荐亮度
  Future<bool> applyRecommendedBrightness() async {
    final recommended = getRecommendedBrightness();
    developer.log('应用推荐亮度: $recommended%', name: 'BrightnessModule');
    
    return await setBrightness(recommended);
  }
}