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

// WiFi 数据模型，基于新的WebSocket架构和 WEBSOCKET_WIFI_API.md 文档定义

import '../models/websocket_models.dart';

/// WiFi 错误码枚举
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

/// WiFi 网络信息
class WiFiNetwork {
  final String ssid;
  final String bssid;
  final int signal; // dBm值
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
    final percentage = signalPercentage;
    if (percentage >= 80) return '优秀';
    if (percentage >= 60) return '良好';
    if (percentage >= 40) return '一般';
    if (percentage >= 20) return '较弱';
    return '很弱';
  }

  /// 是否需要密码
  bool get requiresPassword {
    if (security.isEmpty) return false;

    // 开放网络：只包含 [ESS] 和/或 [UTF-8] 的网络不需要密码
    final openNetworkPattern =
        RegExp(r'^\[ESS\](\[UTF-8\])?$|^\[ESS\]\[UTF-8\]$');
    if (openNetworkPattern.hasMatch(security)) {
      return false;
    }

    // 加密网络：包含 WPA、WPA2、PSK、WEP 等关键字的网络需要密码
    final encryptionKeywords = ['WPA', 'WPA2', 'PSK', 'WEP', 'TKIP', 'CCMP'];
    return encryptionKeywords.any((keyword) => security.contains(keyword));
  }

  /// 是否为加密网络（别名）
  bool get isSecured => requiresPassword;

  /// 信号强度百分比 - 将 dBm 值转换为百分比
  int get signalPercentage {
    // signal 是 dBm 值（通常为负数，如 -81）
    // 转换规则：
    // -30 dBm 或更高 = 100%
    // -50 dBm = 75%
    // -60 dBm = 50%
    // -70 dBm = 25%
    // -80 dBm 或更低 = 0%

    if (signal >= -30) return 100;
    if (signal <= -80) return 0;

    // 使用线性插值计算中间值
    if (signal >= -50) {
      // -30 到 -50 之间：100% 到 75%
      return (100 - ((-30 - signal) / 20) * 25).round();
    } else if (signal >= -60) {
      // -50 到 -60 之间：75% 到 50%
      return (75 - ((-50 - signal) / 10) * 25).round();
    } else if (signal >= -70) {
      // -60 到 -70 之间：50% 到 25%
      return (50 - ((-60 - signal) / 10) * 25).round();
    } else {
      // -70 到 -80 之间：25% 到 0%
      return (25 - ((-70 - signal) / 10) * 25).round();
    }
  }

  /// 获取 dBm 值的字符串表示
  String get signalDbm => '${signal} dBm';
}

/// WiFi 状态信息
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

  /// 创建状态副本，允许修改部分字段
  WiFiStatus copyWith({
    bool? enabled,
    bool? connected,
    String? ssid,
    String? bssid,
    String? interface,
    String? ip,
    int? signal,
    String? security,
    int? channel,
    int? frequencyMhz,
  }) {
    return WiFiStatus(
      enabled: enabled ?? this.enabled,
      connected: connected ?? this.connected,
      ssid: ssid ?? this.ssid,
      bssid: bssid ?? this.bssid,
      interface: interface ?? this.interface,
      ip: ip ?? this.ip,
      signal: signal ?? this.signal,
      security: security ?? this.security,
      channel: channel ?? this.channel,
      frequencyMhz: frequencyMhz ?? this.frequencyMhz,
    );
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

/// WiFi 扫描结果
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

/// WiFi 请求类型常量
class WiFiRequestTypes {
  // 按照 WEBSOCKET_WIFI_API.md 统一为 *_request 后缀
  static const String toggle = 'wifi_enable_request';
  static const String getStatus = 'wifi_status_request';
  static const String scan = 'wifi_scan_request';
  static const String connect = 'wifi_connect_request';
  static const String disconnect = 'wifi_disconnect_request';
}

/// WiFi 响应类型常量
class WiFiResponseTypes {
  static const String enable = 'wifi_enable_response';
  static const String status = 'wifi_status_response';
  static const String scan = 'wifi_scan_response';
  static const String connect = 'wifi_connect_response';
  static const String disconnect = 'wifi_disconnect_response';
}

/// WiFi 事件类型常量
class WiFiEventTypes {
  static const String statusChanged = 'wifi_status_changed';
  static const String scanCompleted = 'wifi_scan_completed';
  static const String connectionChanged = 'wifi_connection_changed';
}

/// WiFi 请求构建器
class WiFiRequestBuilder {
  /// 创建开关WiFi请求
  static WebSocketRequest createToggleRequest({
    required bool enable,
    String? requestId,
  }) {
    return WebSocketRequest(
      requestId: requestId ?? 'req-${DateTime.now().millisecondsSinceEpoch}',
      type: WiFiRequestTypes.toggle,
      data: {'enable': enable},
    );
  }

  /// 创建获取状态请求
  static WebSocketRequest createGetStatusRequest({String? requestId}) {
    return WebSocketRequest(
      requestId: requestId ?? 'req-${DateTime.now().millisecondsSinceEpoch}',
      type: WiFiRequestTypes.getStatus,
      data: {},
    );
  }

  /// 创建扫描请求
  static WebSocketRequest createScanRequest({String? requestId}) {
    return WebSocketRequest(
      requestId: requestId ?? 'req-${DateTime.now().millisecondsSinceEpoch}',
      type: WiFiRequestTypes.scan,
      data: {'rescan': true},
    );
  }

  /// 创建连接请求
  static WebSocketRequest createConnectRequest({
    required String ssid,
    String? password,
    String? requestId,
  }) {
    final data = <String, dynamic>{'ssid': ssid};
    if (password != null && password.isNotEmpty) {
      data['password'] = password;
    }

    return WebSocketRequest(
      requestId: requestId ?? 'req-${DateTime.now().millisecondsSinceEpoch}',
      type: WiFiRequestTypes.connect,
      data: data,
    );
  }

  /// 创建断开连接请求
  static WebSocketRequest createDisconnectRequest({String? requestId}) {
    return WebSocketRequest(
      requestId: requestId ?? 'req-${DateTime.now().millisecondsSinceEpoch}',
      type: WiFiRequestTypes.disconnect,
      data: {},
    );
  }
}

/// WiFi 响应解析器
class WiFiResponseParser {
  /// 解析WiFi状态响应
  static WiFiStatus? parseStatusResponse(WebSocketResponse response) {
    // 校验类型
    if (response.type != WiFiResponseTypes.status) {
      return null;
    }
    if (!response.success || response.data.isEmpty) {
      return null;
    }

    return WiFiStatus.fromJson(response.data);
  }

  /// 解析扫描结果响应
  static WiFiScanResult? parseScanResponse(WebSocketResponse response) {
    // 校验类型
    if (response.type != WiFiResponseTypes.scan) {
      return null;
    }
    if (!response.success || response.data.isEmpty) {
      return null;
    }

    return WiFiScanResult.fromJson(response.data);
  }

  /// 解析启用/禁用响应，返回最终 enabled 值
  static bool? parseEnableResponse(WebSocketResponse response) {
    if (response.type != WiFiResponseTypes.enable) {
      return null;
    }
    if (!response.success) {
      return null;
    }
    final enabled =
        (response.data['enable'] ?? response.data['enabled']) as bool?;
    return enabled;
  }

  /// 解析连接响应，返回是否成功
  static bool? parseConnectResponse(WebSocketResponse response) {
    if (response.type != WiFiResponseTypes.connect) {
      return null;
    }
    return response.success ? true : false;
  }

  /// 解析断开响应，返回是否成功
  static bool? parseDisconnectResponse(WebSocketResponse response) {
    if (response.type != WiFiResponseTypes.disconnect) {
      return null;
    }
    return response.success ? true : false;
  }

  /// 解析错误信息
  static WiFiError parseError(WebSocketResponse response) {
    return WiFiError.fromCode(response.errorCode);
  }
}
