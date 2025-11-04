import 'dart:async';
import 'dart:developer' as developer;
import '../models/websocket_models.dart';
import '../models/wifi_models.dart';
import 'websocket_base_module.dart';

/// WiFi WebSocket模块实现
class WiFiModule extends WebSocketBaseModule {
  static const String _moduleId = 'wifi';
  static const String _websocketPath = '/wifi';

  // 状态管理
  WiFiStatus? _currentStatus;
  WiFiScanResult? _lastScanResult;
  bool _isScanning = false;
  bool _isConnecting = false;

  // 状态流控制器
  final StreamController<WiFiStatus> _statusController =
      StreamController<WiFiStatus>.broadcast();
  final StreamController<WiFiScanResult> _scanResultController =
      StreamController<WiFiScanResult>.broadcast();
  final StreamController<bool> _scanningController =
      StreamController<bool>.broadcast();
  final StreamController<bool> _connectingController =
      StreamController<bool>.broadcast();

  @override
  String get moduleId => _moduleId;

  @override
  String get websocketPath => _websocketPath;

  /// WiFi状态流
  Stream<WiFiStatus> get statusStream => _statusController.stream;

  /// 扫描结果流
  Stream<WiFiScanResult> get scanResultStream => _scanResultController.stream;

  /// 扫描状态流
  Stream<bool> get scanningStream => _scanningController.stream;

  /// 连接状态流
  Stream<bool> get connectingStream => _connectingController.stream;

  /// 当前WiFi状态
  WiFiStatus? get currentStatus => _currentStatus;

  /// 最后扫描结果
  WiFiScanResult? get lastScanResult => _lastScanResult;

  /// 是否正在扫描
  bool get isScanning => _isScanning;

  /// 是否正在连接
  bool get isConnecting => _isConnecting;

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
    developer.log('WiFi模块初始化', name: 'WiFiModule');

    // 初始化状态
    _currentStatus = null;
    _lastScanResult = null;
    _isScanning = false;
    _isConnecting = false;
  }

  @override
  Future<void> onDispose() async {
    developer.log('WiFi模块释放', name: 'WiFiModule');

    // 关闭所有流控制器
    await _statusController.close();
    await _scanResultController.close();
    await _scanningController.close();
    await _connectingController.close();
  }

  @override
  Future<WebSocketResponse> onHandleMessage(WebSocketRequest request) async {
    // WiFi模块通常不需要处理来自服务器的请求消息
    // 这里可以根据需要添加处理逻辑
    developer.log('WiFi模块收到请求消息: ${request.type}', name: 'WiFiModule');

    // 返回一个默认的成功响应，类型按 WiFiResponseTypes 与请求类型成对映射
    String responseType;
    switch (request.type) {
      case WiFiRequestTypes.toggle:
        responseType = WiFiResponseTypes.enable;
        break;
      case WiFiRequestTypes.getStatus:
        responseType = WiFiResponseTypes.status;
        break;
      case WiFiRequestTypes.scan:
        responseType = WiFiResponseTypes.scan;
        break;
      case WiFiRequestTypes.connect:
        responseType = WiFiResponseTypes.connect;
        break;
      case WiFiRequestTypes.disconnect:
        responseType = WiFiResponseTypes.disconnect;
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
    developer.log('WiFi模块收到事件: ${event.type}', name: 'WiFiModule');

    try {
      switch (event.type) {
        case WiFiEventTypes.statusChanged:
          _handleStatusChangedEvent(event);
          break;
        case WiFiEventTypes.scanCompleted:
          _handleScanCompletedEvent(event);
          break;
        case WiFiEventTypes.connectionChanged:
          _handleConnectionChangedEvent(event);
          break;
        default:
          developer.log('未知WiFi事件类型: ${event.type}', name: 'WiFiModule');
      }
    } catch (e, stackTrace) {
      developer.log(
        '处理WiFi事件失败: ${event.type}, 错误: $e',
        name: 'WiFiModule',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  @override
  void onConnectionStateChanged(WebSocketConnectionState state) {
    super.onConnectionStateChanged(state);

    if (state == WebSocketConnectionState.connected) {
      // 连接成功后立即获取WiFi状态
      getStatus().catchError((e) {
        developer.log('获取WiFi状态失败: $e', name: 'WiFiModule');
        return null;
      });
    }
  }

  /// 开关WiFi
  Future<bool> toggleWiFi(bool enable) async {
    try {
      developer.log('开关WiFi: $enable', name: 'WiFiModule');

      // 立即进行乐观更新：先根据用户操作更新本地状态，提升交互响应
      final prevStatus = _currentStatus ??
          const WiFiStatus(enabled: false, connected: false);
      final optimisticStatus = prevStatus.copyWith(enabled: enable);
      _updateStatus(optimisticStatus);
      developer.log('即时乐观更新WiFi启用状态: $enable', name: 'WiFiModule');

      // 发送后端请求
      final request = WiFiRequestBuilder.createToggleRequest(enable: enable);
      final response = await sendRequest(request);

      if (response.success) {
        // 使用解析器进行类型校验与解析
        final srvEnabled = WiFiResponseParser.parseEnableResponse(response);
        if (srvEnabled != null) {
          final newStatus = (_currentStatus ??
                  const WiFiStatus(enabled: false, connected: false))
              .copyWith(enabled: srvEnabled);
          _updateStatus(newStatus);
          developer.log('根据服务端响应校正WiFi启用状态: $srvEnabled', name: 'WiFiModule');
        }

        // 后台刷新完整状态，不阻塞UI
        getStatus().catchError((e) {
          developer.log('刷新WiFi状态失败(后台): $e', name: 'WiFiModule');
          return null;
        });
        return true;
      } else {
        final error = WiFiResponseParser.parseError(response);
        developer.log('开关WiFi失败: ${error.message}', name: 'WiFiModule');
        // 操作失败则回滚乐观更新
        _updateStatus(prevStatus);
        return false;
      }
    } catch (e, stackTrace) {
      developer.log(
        '开关WiFi异常: $e',
        name: 'WiFiModule',
        error: e,
        stackTrace: stackTrace,
      );
      // 异常也回滚乐观更新到之前状态
      final prevStatus = _currentStatus ??
          const WiFiStatus(enabled: false, connected: false);
      _updateStatus(prevStatus);
      return false;
    }
  }

  /// 获取WiFi状态
  Future<WiFiStatus?> getStatus() async {
    try {
      developer.log('获取WiFi状态', name: 'WiFiModule');

      final request = WiFiRequestBuilder.createGetStatusRequest();
      final response = await sendRequest(request);

      if (response.success) {
        final status = WiFiResponseParser.parseStatusResponse(response);
        if (status != null) {
          _updateStatus(status);
          return status;
        }
      } else {
        final error = WiFiResponseParser.parseError(response);
        developer.log('获取WiFi状态失败: ${error.message}', name: 'WiFiModule');
      }

      return null;
    } catch (e, stackTrace) {
      developer.log(
        '获取WiFi状态异常: $e',
        name: 'WiFiModule',
        error: e,
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  /// 扫描WiFi网络
  Future<WiFiScanResult?> scanNetworks() async {
    if (_isScanning) {
      developer.log('WiFi扫描已在进行中', name: 'WiFiModule');
      return _lastScanResult;
    }

    try {
      developer.log('开始WiFi扫描', name: 'WiFiModule');

      _updateScanningState(true);

      final request = WiFiRequestBuilder.createScanRequest();
      final response = await sendRequest(request);

      if (response.success) {
        final scanResult = WiFiResponseParser.parseScanResponse(response);
        if (scanResult != null) {
          _updateScanResult(scanResult);
          return scanResult;
        }
      } else {
        final error = WiFiResponseParser.parseError(response);
        developer.log('WiFi扫描失败: ${error.message}', name: 'WiFiModule');
      }

      return null;
    } catch (e, stackTrace) {
      developer.log(
        'WiFi扫描异常: $e',
        name: 'WiFiModule',
        error: e,
        stackTrace: stackTrace,
      );
      return null;
    } finally {
      _updateScanningState(false);
    }
  }

  /// 连接WiFi网络
  Future<bool> connectToNetwork(String ssid, {String? password}) async {
    if (_isConnecting) {
      developer.log('WiFi连接已在进行中', name: 'WiFiModule');
      return false;
    }

    try {
      developer.log('连接WiFi网络: $ssid', name: 'WiFiModule');

      _updateConnectingState(true);

      final request = WiFiRequestBuilder.createConnectRequest(
        ssid: ssid,
        password: password,
      );
      final response = await sendRequest(request);

      final ok = WiFiResponseParser.parseConnectResponse(response);
      if (ok == true) {
        await getStatus();
        return true;
      }

      final error = WiFiResponseParser.parseError(response);
      developer.log('WiFi连接失败: ${error.message}', name: 'WiFiModule');
      return false;
    } catch (e, stackTrace) {
      developer.log(
        'WiFi连接异常: $e',
        name: 'WiFiModule',
        error: e,
        stackTrace: stackTrace,
      );
      return false;
    } finally {
      _updateConnectingState(false);
    }
  }

  /// 断开WiFi连接
  Future<bool> disconnect() async {
    try {
      developer.log('断开WiFi连接', name: 'WiFiModule');

      final request = WiFiRequestBuilder.createDisconnectRequest();
      final response = await sendRequest(request);

      final ok = WiFiResponseParser.parseDisconnectResponse(response);
      if (ok == true) {
        await getStatus();
        return true;
      }

      final error = WiFiResponseParser.parseError(response);
      developer.log('WiFi断开失败: ${error.message}', name: 'WiFiModule');
      return false;
    } catch (e, stackTrace) {
      developer.log(
        'WiFi断开异常: $e',
        name: 'WiFiModule',
        error: e,
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  /// 处理状态变化事件
  void _handleStatusChangedEvent(WebSocketEvent event) {
    try {
      final status = WiFiStatus.fromJson(event.data);
      _updateStatus(status);

      developer.log('WiFi状态变化: ${status.statusDescription}',
          name: 'WiFiModule');
    } catch (e) {
      developer.log('解析WiFi状态事件失败: $e', name: 'WiFiModule');
    }
  }

  /// 处理扫描完成事件
  void _handleScanCompletedEvent(WebSocketEvent event) {
    try {
      final scanResult = WiFiScanResult.fromJson(event.data);
      _updateScanResult(scanResult);
      _updateScanningState(false);

      developer.log('WiFi扫描完成，发现${scanResult.networks.length}个网络',
          name: 'WiFiModule');
    } catch (e) {
      developer.log('解析WiFi扫描事件失败: $e', name: 'WiFiModule');
      _updateScanningState(false);
    }
  }

  /// 处理连接变化事件
  void _handleConnectionChangedEvent(WebSocketEvent event) {
    try {
      final connected = event.data['connected'] as bool? ?? false;
      final ssid = event.data['ssid'] as String?;

      _updateConnectingState(false);

      if (connected && ssid != null) {
        developer.log('WiFi连接成功: $ssid', name: 'WiFiModule');
      } else {
        developer.log('WiFi连接断开', name: 'WiFiModule');
      }

      // 刷新状态
      getStatus().catchError((e) {
        developer.log('刷新WiFi状态失败: $e', name: 'WiFiModule');
        return null;
      });
    } catch (e) {
      developer.log('解析WiFi连接事件失败: $e', name: 'WiFiModule');
      _updateConnectingState(false);
    }
  }

  /// 更新WiFi状态
  void _updateStatus(WiFiStatus status) {
    _currentStatus = status;
    if (!_statusController.isClosed) {
      _statusController.add(status);
    }

    // 发送模块事件
    emitEvent('status_updated', status.toJson());
  }

  /// 更新扫描结果
  void _updateScanResult(WiFiScanResult scanResult) {
    _lastScanResult = scanResult;
    if (!_scanResultController.isClosed) {
      _scanResultController.add(scanResult);
    }

    // 发送模块事件
    emitEvent('scan_completed', scanResult.toJson());
  }

  /// 更新扫描状态
  void _updateScanningState(bool scanning) {
    _isScanning = scanning;
    if (!_scanningController.isClosed) {
      _scanningController.add(scanning);
    }

    // 发送模块事件
    emitEvent('scanning_state_changed', {'scanning': scanning});
  }

  /// 更新连接状态
  void _updateConnectingState(bool connecting) {
    _isConnecting = connecting;
    if (!_connectingController.isClosed) {
      _connectingController.add(connecting);
    }

    // 发送模块事件
    emitEvent('connecting_state_changed', {'connecting': connecting});
  }
}
