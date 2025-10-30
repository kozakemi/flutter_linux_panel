import 'dart:async';

import '../models/wifi_models.dart';
import 'websocket_client.dart';

/// Wi-Fi WebSocket 服务
/// 基于 WEBSOCKET_WIFI_API.md 文档实现
class WiFiWebSocketService {
  static WiFiWebSocketService? _instance;
  static WiFiWebSocketService get instance =>
      _instance ??= WiFiWebSocketService._();

  WiFiWebSocketService._();

  WebSocketClient? _client;
  WiFiStatus _currentStatus =
      const WiFiStatus(enabled: false, connected: false);
  WiFiScanResult _lastScanResult = const WiFiScanResult(networks: []);

  // 流控制器
  final StreamController<WiFiStatus> _statusController =
      StreamController<WiFiStatus>.broadcast();
  final StreamController<WiFiScanResult> _scanController =
      StreamController<WiFiScanResult>.broadcast();
  final StreamController<String> _connectionEventController =
      StreamController<String>.broadcast();

  /// Wi-Fi 状态流
  Stream<WiFiStatus> get statusStream => _statusController.stream;

  /// 扫描结果流
  Stream<WiFiScanResult> get scanStream => _scanController.stream;

  /// 连接事件流（连接/断开事件）
  Stream<String> get connectionEventStream => _connectionEventController.stream;

  /// 当前 Wi-Fi 状态
  WiFiStatus get currentStatus => _currentStatus;

  /// 最后的扫描结果
  WiFiScanResult get lastScanResult => _lastScanResult;

  /// WebSocket 连接状态
  WebSocketConnectionState get connectionState =>
      _client?.state ?? WebSocketConnectionState.disconnected;

  /// WebSocket 连接状态流
  Stream<WebSocketConnectionState> get connectionStateStream =>
      _client?.stateStream ?? const Stream.empty();

  /// 初始化服务
  Future<void> initialize({String url = 'ws://172.20.10.2:8080'}) async {
    if (_client != null) {
      await _client!.disconnect();
    }

    _client = WebSocketClient(url: url);

    // 监听事件
    _client!.eventStream.listen(_handleEvent);

    // 连接到服务器
    await _client!.connect();

    // 初始化时获取状态
    await refreshStatus();
  }

  /// 处理 WebSocket 事件
  void _handleEvent(WebSocketEvent event) {
    switch (event.type) {
      case 'wifi_connect_event':
        final connected = event.data['connected'] as bool? ?? false;
        final ssid = event.data['ssid'] as String?;
        if (connected && ssid != null) {
          _connectionEventController.add('已连接到 $ssid');
        }
        refreshStatus(); // 刷新状态
        break;

      case 'wifi_disconnect_event':
        final ssid = event.data['ssid'] as String?;
        if (ssid != null) {
          _connectionEventController.add('已断开 $ssid');
        }
        refreshStatus(); // 刷新状态
        break;

      case 'wifi_scan_event':
        final scanResult = WiFiScanResult.fromJson(event.data);
        _lastScanResult = scanResult;
        _scanController.add(scanResult);
        break;
    }
  }

  /// 开关 Wi-Fi
  Future<WiFiError> enableWiFi(bool enable) async {
    if (_client == null || !_client!.isConnected) {
      print('WiFi 服务: WebSocket 未连接，无法${enable ? '开启' : '关闭'} Wi-Fi');
      return WiFiError.notConnected;
    }

    try {
      print('WiFi 服务: ${enable ? '开启' : '关闭'} Wi-Fi');
      final request = WebSocketRequest(
        type: 'wifi_enable_request',
        data: {'enable': enable},
      );

      final response = await _client!.sendRequest(request);
      print('WiFi 服务: Wi-Fi ${enable ? '开启' : '关闭'}响应 - success: ${response.success}, error: ${response.error}');

      if (response.success) {
        print('WiFi 服务: Wi-Fi ${enable ? '开启' : '关闭'}成功，刷新状态');
        // 更新状态
        await refreshStatus();
        return WiFiError.ok;
      } else {
        print('WiFi 服务: Wi-Fi ${enable ? '开启' : '关闭'}失败 - ${response.wifiError.message}');
        return response.wifiError;
      }
    } catch (e, stackTrace) {
      print('WiFi 服务: Wi-Fi ${enable ? '开启' : '关闭'}异常 - $e');
      print('WiFi 服务: 堆栈跟踪 - $stackTrace');
      return WiFiError.internal;
    }
  }

  /// 获取 Wi-Fi 状态
  Future<WiFiError> refreshStatus() async {
    if (_client == null || !_client!.isConnected) {
      print('WiFi 服务: WebSocket 未连接');
      return WiFiError.notConnected;
    }

    try {
      print('WiFi 服务: 请求状态更新');
      final request = WebSocketRequest(
        type: 'wifi_status_request',
        data: {},
      );

      final response = await _client!.sendRequest(request);
      print('WiFi 服务: 收到状态响应 - success: ${response.success}, error: ${response.error}');
      print('WiFi 服务: 响应数据: ${response.data}');

      if (response.success) {
        _currentStatus = WiFiStatus.fromJson(response.data);
        print('WiFi 服务: 解析状态 - enabled: ${_currentStatus.enabled}, connected: ${_currentStatus.connected}');
        _statusController.add(_currentStatus);
        return WiFiError.ok;
      } else {
        print('WiFi 服务: 状态请求失败 - ${response.wifiError.message}');
        return response.wifiError;
      }
    } catch (e, stackTrace) {
      print('WiFi 服务: 状态请求异常 - $e');
      print('WiFi 服务: 堆栈跟踪 - $stackTrace');
      return WiFiError.internal;
    }
  }

  /// 扫描 Wi-Fi 网络
  Future<WiFiError> scanNetworks({bool rescan = true}) async {
    if (_client == null || !_client!.isConnected) {
      print('WiFi 服务: WebSocket 未连接，无法扫描网络');
      return WiFiError.notConnected;
    }

    try {
      print('WiFi 服务: 开始扫描网络 (rescan: $rescan)');
      final request = WebSocketRequest(
        type: 'wifi_scan_request',
        data: {'rescan': rescan},
      );

      final response = await _client!.sendRequest(request);
      print('WiFi 服务: 扫描响应 - success: ${response.success}, error: ${response.error}');
      print('WiFi 服务: 扫描数据: ${response.data}');

      if (response.success) {
        _lastScanResult = WiFiScanResult.fromJson(response.data);
        print('WiFi 服务: 扫描到 ${_lastScanResult.networks.length} 个网络');
        _scanController.add(_lastScanResult);
        return WiFiError.ok;
      } else {
        print('WiFi 服务: 扫描失败 - ${response.wifiError.message}');
        return response.wifiError;
      }
    } catch (e, stackTrace) {
      print('WiFi 服务: 扫描异常 - $e');
      print('WiFi 服务: 堆栈跟踪 - $stackTrace');
      return WiFiError.internal;
    }
  }

  /// 连接到 Wi-Fi 网络
  Future<WiFiError> connectToNetwork({
    required String ssid,
    String password = '',
    int timeoutMs = 20000,
  }) async {
    if (_client == null || !_client!.isConnected) {
      return WiFiError.notConnected;
    }

    try {
      final request = WebSocketRequest(
        type: 'wifi_connect_request',
        data: {
          'ssid': ssid,
          'password': password,
          'timeout_ms': timeoutMs,
        },
      );

      final response = await _client!.sendRequest(request);

      if (response.success) {
        // 连接成功后刷新状态
        await refreshStatus();
        return WiFiError.ok;
      } else {
        return response.wifiError;
      }
    } catch (e) {
      return WiFiError.internal;
    }
  }

  /// 断开 Wi-Fi 连接
  Future<WiFiError> disconnectFromNetwork({String? ssid}) async {
    if (_client == null || !_client!.isConnected) {
      return WiFiError.notConnected;
    }

    try {
      final data = <String, dynamic>{};
      if (ssid != null) {
        data['ssid'] = ssid;
      }

      final request = WebSocketRequest(
        type: 'wifi_disconnect_request',
        data: data,
      );

      final response = await _client!.sendRequest(request);

      if (response.success) {
        // 断开后刷新状态
        await refreshStatus();
        return WiFiError.ok;
      } else {
        return response.wifiError;
      }
    } catch (e) {
      return WiFiError.internal;
    }
  }

  /// 获取网络信息（从扫描结果中查找）
  WiFiNetwork? getNetworkInfo(String ssid) {
    return _lastScanResult.networks
        .where((network) => network.ssid == ssid)
        .firstOrNull;
  }

  /// 检查网络是否需要密码
  bool networkRequiresPassword(String ssid) {
    final network = getNetworkInfo(ssid);
    return network?.requiresPassword ?? true;
  }

  /// 获取网络信号强度
  int getNetworkSignal(String ssid) {
    final network = getNetworkInfo(ssid);
    return network?.signal ?? 0;
  }

  /// 获取网络安全类型
  String getNetworkSecurity(String ssid) {
    final network = getNetworkInfo(ssid);
    return network?.security ?? 'Unknown';
  }

  /// 检查是否已连接到指定网络
  bool isConnectedTo(String ssid) {
    return _currentStatus.connected && _currentStatus.ssid == ssid;
  }

  /// 获取已保存的网络列表
  List<WiFiNetwork> get savedNetworks {
    return _lastScanResult.recordedNetworks;
  }

  /// 获取其他网络列表
  List<WiFiNetwork> get otherNetworks {
    return _lastScanResult.otherNetworks;
  }

  /// 关闭服务
  Future<void> dispose() async {
    await _client?.disconnect();
    _client?.dispose();
    _client = null;

    await _statusController.close();
    await _scanController.close();
    await _connectionEventController.close();
  }
}

/// 扩展方法，为 List 添加 firstOrNull
extension ListExtension<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
