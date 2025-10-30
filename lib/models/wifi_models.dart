// Wi-Fi 数据模型，基于 WEBSOCKET_WIFI_API.md 文档定义

/// Wi-Fi 错误码枚举
enum WiFiError {
  ok(0),
  unknown(-1),
  badRequest(1),
  notSupported(2),
  wifiDisabled(3),
  alreadyConnected(4),
  networkNotFound(5),
  authFailed(6),
  timeout(7),
  internal(8),
  permission(9),
  busy(10),
  invalidSsid(11),
  invalidPassword(12),
  interfaceDown(13),
  toolError(14),
  configError(15),
  ioError(16),
  notConnected(17);

  const WiFiError(this.code);
  final int code;

  static WiFiError fromCode(int code) {
    return WiFiError.values.firstWhere(
      (e) => e.code == code,
      orElse: () => WiFiError.unknown,
    );
  }

  String get message {
    switch (this) {
      case WiFiError.ok:
        return '成功';
      case WiFiError.unknown:
        return '未知错误';
      case WiFiError.badRequest:
        return '请求数据错误';
      case WiFiError.notSupported:
        return '操作不支持';
      case WiFiError.wifiDisabled:
        return 'Wi-Fi 已关闭';
      case WiFiError.alreadyConnected:
        return '已连接到该网络';
      case WiFiError.networkNotFound:
        return '未找到网络';
      case WiFiError.authFailed:
        return '认证失败，请检查密码';
      case WiFiError.timeout:
        return '连接超时';
      case WiFiError.internal:
        return '内部错误';
      case WiFiError.permission:
        return '权限不足';
      case WiFiError.busy:
        return '设备繁忙';
      case WiFiError.invalidSsid:
        return '无效的网络名称';
      case WiFiError.invalidPassword:
        return '无效的密码';
      case WiFiError.interfaceDown:
        return '网络接口未启动';
      case WiFiError.toolError:
        return '系统工具错误';
      case WiFiError.configError:
        return '配置错误';
      case WiFiError.ioError:
        return 'I/O 错误';
      case WiFiError.notConnected:
        return '未连接';
    }
  }
}

/// WebSocket 消息基类
abstract class WebSocketMessage {
  final String type;
  final String? requestId;

  const WebSocketMessage({
    required this.type,
    this.requestId,
  });

  Map<String, dynamic> toJson();
}

/// WebSocket 请求消息
class WebSocketRequest extends WebSocketMessage {
  final Map<String, dynamic> data;

  const WebSocketRequest({
    required super.type,
    super.requestId,
    required this.data,
  });

  @override
  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{
      'type': type,
      'data': data,
    };
    if (requestId != null) {
      json['request_id'] = requestId;
    }
    return json;
  }
}

/// WebSocket 响应消息
class WebSocketResponse extends WebSocketMessage {
  final bool success;
  final int error;
  final String? message;
  final Map<String, dynamic> data;

  const WebSocketResponse({
    required super.type,
    super.requestId,
    required this.success,
    required this.error,
    this.message,
    required this.data,
  });

  factory WebSocketResponse.fromJson(Map<String, dynamic> json) {
    return WebSocketResponse(
      type: json['type'] as String,
      requestId: json['request_id'] as String?,
      success: json['success'] as bool,
      error: json['error'] as int,
      message: json['message'] as String?,
      data: json['data'] as Map<String, dynamic>? ?? {},
    );
  }

  @override
  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{
      'type': type,
      'success': success,
      'error': error,
      'data': data,
    };
    if (requestId != null) {
      json['request_id'] = requestId;
    }
    if (message != null) {
      json['message'] = message;
    }
    return json;
  }

  WiFiError get wifiError => WiFiError.fromCode(error);
}

/// WebSocket 事件消息
class WebSocketEvent extends WebSocketMessage {
  final Map<String, dynamic> data;

  const WebSocketEvent({
    required super.type,
    required this.data,
  });

  factory WebSocketEvent.fromJson(Map<String, dynamic> json) {
    return WebSocketEvent(
      type: json['type'] as String,
      data: json['data'] as Map<String, dynamic>? ?? {},
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      'type': type,
      'data': data,
    };
  }
}

/// Wi-Fi 网络信息
class WiFiNetwork {
  final String ssid;
  final String bssid;
  final int signal; // 0-100
  final String security;
  final int channel;
  final int frequencyMhz;
  final bool recorded; // 是否已保存

  const WiFiNetwork({
    required this.ssid,
    required this.bssid,
    required this.signal,
    required this.security,
    required this.channel,
    required this.frequencyMhz,
    required this.recorded,
  });

  factory WiFiNetwork.fromJson(Map<String, dynamic> json) {
    return WiFiNetwork(
      ssid: json['ssid'] as String? ?? '',
      bssid: json['bssid'] as String? ?? '',
      signal: json['signal'] as int? ?? 0,
      security: json['security'] as String? ?? 'Open',
      channel: json['channel'] as int? ?? 0,
      frequencyMhz: json['frequency_mhz'] as int? ?? 0,
      recorded: json['recorded'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'ssid': ssid,
      'bssid': bssid,
      'signal': signal,
      'security': security,
      'channel': channel,
      'frequency_mhz': frequencyMhz,
      'recorded': recorded,
    };
  }

  /// 获取信号强度描述
  String get signalStrength {
    if (signal >= 80) return '优秀';
    if (signal >= 60) return '良好';
    if (signal >= 40) return '一般';
    if (signal >= 20) return '较弱';
    return '很弱';
  }

  /// 是否需要密码
  bool get requiresPassword {
    return security != 'Open' && security.isNotEmpty;
  }

  /// 是否为加密网络（别名）
  bool get isSecured => requiresPassword;

  /// 信号强度百分比
  int get signalPercentage => signal;
}

/// Wi-Fi 状态信息
class WiFiStatus {
  final bool enabled;
  final bool connected;
  final String? ssid;
  final String? bssid;
  final String? interface;
  final String? ip;
  final int? signal;
  final String? security;
  final int? channel;
  final int? frequencyMhz;

  const WiFiStatus({
    required this.enabled,
    required this.connected,
    this.ssid,
    this.bssid,
    this.interface,
    this.ip,
    this.signal,
    this.security,
    this.channel,
    this.frequencyMhz,
  });

  factory WiFiStatus.fromJson(Map<String, dynamic> json) {
    return WiFiStatus(
      // 兼容服务器返回的 'enable' 字段和标准的 'enabled' 字段
      enabled: (json['enable'] ?? json['enabled']) as bool? ?? false,
      connected: json['connected'] as bool? ?? false,
      ssid: json['ssid'] as String?,
      bssid: json['bssid'] as String?,
      interface: json['interface'] as String?,
      ip: json['ip'] as String?,
      signal: json['signal'] as int?,
      security: json['security'] as String?,
      channel: json['channel'] as int?,
      frequencyMhz: json['frequency_mhz'] as int?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'enabled': enabled,
      'connected': connected,
      if (ssid != null) 'ssid': ssid,
      if (bssid != null) 'bssid': bssid,
      if (interface != null) 'interface': interface,
      if (ip != null) 'ip': ip,
      if (signal != null) 'signal': signal,
      if (security != null) 'security': security,
      if (channel != null) 'channel': channel,
      if (frequencyMhz != null) 'frequency_mhz': frequencyMhz,
    };
  }

  /// 获取连接状态描述
  String get statusDescription {
    if (!enabled) return 'Wi-Fi 已关闭';
    if (!connected) return '未连接';
    return '已连接到 ${ssid ?? '未知网络'}';
  }

  /// 当前连接的网络信息
  WiFiNetwork? get currentNetwork {
    if (!connected || ssid == null) return null;
    
    return WiFiNetwork(
      ssid: ssid!,
      bssid: bssid ?? '',
      signal: signal ?? 0,
      security: security ?? 'Open',
      channel: channel ?? 0,
      frequencyMhz: frequencyMhz ?? 0,
      recorded: true, // 已连接的网络通常是已保存的
    );
  }
}

/// Wi-Fi 扫描结果
class WiFiScanResult {
  final List<WiFiNetwork> networks;

  const WiFiScanResult({
    required this.networks,
  });

  factory WiFiScanResult.fromJson(Map<String, dynamic> json) {
    final networksJson = json['networks'] as List<dynamic>? ?? [];
    final networks = networksJson
        .map((e) => WiFiNetwork.fromJson(e as Map<String, dynamic>))
        .toList();
    
    return WiFiScanResult(networks: networks);
  }

  Map<String, dynamic> toJson() {
    return {
      'networks': networks.map((e) => e.toJson()).toList(),
    };
  }

  /// 按信号强度排序的网络列表
  List<WiFiNetwork> get sortedBySignal {
    final sorted = List<WiFiNetwork>.from(networks);
    sorted.sort((a, b) => b.signal.compareTo(a.signal));
    return sorted;
  }

  /// 已保存的网络
  List<WiFiNetwork> get recordedNetworks {
    return networks.where((n) => n.recorded).toList();
  }

  /// 其他网络
  List<WiFiNetwork> get otherNetworks {
    return networks.where((n) => !n.recorded).toList();
  }
}