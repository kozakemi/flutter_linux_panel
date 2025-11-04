// 亮度控制数据模型，基于新的WebSocket架构和 WEBSOCKET_BRIGHTNESS_API.md 文档定义

import '../models/websocket_models.dart';

/// 亮度控制错误码枚举
enum BrightnessError {
  ok(0),
  unknown(-1),
  badRequest(1),
  notSupported(2),
  deviceNotFound(3),
  permissionDenied(4),
  invalidValue(5),
  systemError(6),
  timeout(7),
  busy(8),
  configError(9),
  ioError(10);

  const BrightnessError(this.code);
  final int code;

  static BrightnessError fromCode(int code) {
    return BrightnessError.values.firstWhere(
      (e) => e.code == code,
      orElse: () => BrightnessError.unknown,
    );
  }

  String get message {
    switch (this) {
      case BrightnessError.ok:
        return '成功';
      case BrightnessError.unknown:
        return '未知错误';
      case BrightnessError.badRequest:
        return '请求数据错误';
      case BrightnessError.notSupported:
        return '操作不支持';
      case BrightnessError.deviceNotFound:
        return '未找到亮度设备';
      case BrightnessError.permissionDenied:
        return '权限不足';
      case BrightnessError.invalidValue:
        return '无效的亮度值';
      case BrightnessError.systemError:
        return '系统错误';
      case BrightnessError.timeout:
        return '操作超时';
      case BrightnessError.busy:
        return '设备繁忙';
      case BrightnessError.configError:
        return '配置错误';
      case BrightnessError.ioError:
        return 'I/O 错误';
    }
  }
}

/// 亮度状态信息
class BrightnessStatus {
  final int current; // 当前亮度值 (0-100)
  final int max; // 最大亮度值
  final bool autoEnabled; // 是否启用自动亮度
  final bool available; // 亮度控制是否可用

  const BrightnessStatus({
    required this.current,
    required this.max,
    required this.autoEnabled,
    required this.available,
  });

  factory BrightnessStatus.fromJson(Map<String, dynamic> json) {
    return BrightnessStatus(
      // 兼容 API: 使用 brightness(0-100)；兼容旧字段 current
      current: (json['brightness'] as int?) ?? (json['current'] as int?) ?? 0,
      // 最大亮度：如未提供，默认 100
      max: json['max'] as int? ?? 100,
      // 自动亮度：API 为 auto_brightness；兼容旧字段 auto_enabled
      autoEnabled:
          (json['auto_brightness'] as bool?) ?? (json['auto_enabled'] as bool?) ?? false,
      // 可用性：如未提供，默认 true
      available: json['available'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      // 对外兼容 API 字段
      'brightness': current,
      'auto_brightness': autoEnabled,
      // 同时保留内部使用字段
      'current': current,
      'max': max,
      'auto_enabled': autoEnabled,
      'available': available,
    };
  }

  /// 创建状态副本，允许修改部分字段
  BrightnessStatus copyWith({
    int? current,
    int? max,
    bool? autoEnabled,
    bool? available,
  }) {
    return BrightnessStatus(
      current: current ?? this.current,
      max: max ?? this.max,
      autoEnabled: autoEnabled ?? this.autoEnabled,
      available: available ?? this.available,
    );
  }

  /// 获取亮度百分比 (0-100)
  int get percentage {
    if (max <= 0) return 0;
    return ((current / max) * 100).round().clamp(0, 100);
  }

  /// 获取亮度描述
  String get description {
    if (!available) return '亮度控制不可用';
    
    final percent = percentage;
    if (autoEnabled) {
      return '自动亮度 ($percent%)';
    }
    
    if (percent >= 80) return '很亮 ($percent%)';
    if (percent >= 60) return '较亮 ($percent%)';
    if (percent >= 40) return '适中 ($percent%)';
    if (percent >= 20) return '较暗 ($percent%)';
    return '很暗 ($percent%)';
  }

  /// 是否为低亮度
  bool get isLowBrightness => percentage < 20;

  /// 是否为高亮度
  bool get isHighBrightness => percentage > 80;
}

/// 亮度请求类型常量
class BrightnessRequestTypes {
  static const String getStatus = 'brightness_status_request';
  static const String setBrightness = 'brightness_set_request';
  static const String setAuto = 'brightness_auto_request';
}

/// 亮度响应类型常量（与请求类型成对存在，紧随其后）
class BrightnessResponseTypes {
  static const String status = 'brightness_status_response';
  static const String set = 'brightness_set_response';
  static const String auto = 'brightness_auto_response';
}

/// 亮度事件类型常量
class BrightnessEventTypes {
  static const String brightnessChanged = 'brightness_changed_event';
  static const String autoModeChanged = 'brightness_auto_changed_event';
}

/// 亮度请求构建器
class BrightnessRequestBuilder {
  /// 创建获取亮度状态请求
  static WebSocketRequest createGetStatusRequest({String? requestId}) {
    return WebSocketRequest(
      requestId: requestId ?? 'req-${DateTime.now().millisecondsSinceEpoch}',
      type: BrightnessRequestTypes.getStatus,
      data: {},
    );
  }

  /// 创建设置亮度请求
  static WebSocketRequest createSetBrightnessRequest({
    required int brightness,
    String? requestId,
  }) {
    return WebSocketRequest(
      requestId: requestId ?? 'req-${DateTime.now().millisecondsSinceEpoch}',
      type: BrightnessRequestTypes.setBrightness,
      data: {'brightness': brightness.clamp(0, 100)},
    );
  }

  /// 创建设置自动亮度请求
  static WebSocketRequest createSetAutoRequest({
    required bool enabled,
    String? requestId,
  }) {
    return WebSocketRequest(
      requestId: requestId ?? 'req-${DateTime.now().millisecondsSinceEpoch}',
      type: BrightnessRequestTypes.setAuto,
      // API 使用 enable 字段
      data: {'enable': enabled},
    );
  }
}

/// 亮度响应解析器
class BrightnessResponseParser {
  /// 解析亮度状态响应
  static BrightnessStatus? parseStatusResponse(WebSocketResponse response) {
    // 校验类型
    if (response.type != BrightnessResponseTypes.status) {
      return null;
    }
    if (!response.success || response.data.isEmpty) {
      return null;
    }

    return BrightnessStatus.fromJson(response.data);
  }

  /// 解析设置亮度响应，返回是否成功
  static bool? parseSetResponse(WebSocketResponse response) {
    if (response.type != BrightnessResponseTypes.set) {
      return null;
    }
    return response.success ? true : false;
  }

  /// 解析自动亮度响应，返回自动亮度状态
  static bool? parseAutoResponse(WebSocketResponse response) {
    if (response.type != BrightnessResponseTypes.auto) {
      return null;
    }
    if (!response.success) {
      return null;
    }
    // API 文档字段为 auto_brightness；兼容旧字段 enabled
    final enabled = (response.data['auto_brightness'] ?? response.data['enabled']) as bool?;
    return enabled;
  }

  /// 解析错误信息
  static BrightnessError parseError(WebSocketResponse response) {
    return BrightnessError.fromCode(response.errorCode);
  }
}

/// 亮度变化事件数据
class BrightnessChangeEvent {
  final int oldValue;
  final int newValue;
  final bool autoMode;
  final DateTime timestamp;

  const BrightnessChangeEvent({
    required this.oldValue,
    required this.newValue,
    required this.autoMode,
    required this.timestamp,
  });

  factory BrightnessChangeEvent.fromJson(Map<String, dynamic> json) {
    return BrightnessChangeEvent(
      oldValue: json['old_value'] as int? ?? 0,
      newValue: json['new_value'] as int? ?? 0,
      autoMode: json['auto_mode'] as bool? ?? false,
      timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'old_value': oldValue,
      'new_value': newValue,
      'auto_mode': autoMode,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  /// 亮度变化量
  int get delta => newValue - oldValue;

  /// 是否为亮度增加
  bool get isIncrease => delta > 0;

  /// 是否为亮度减少
  bool get isDecrease => delta < 0;

  /// 变化描述
  String get description {
    if (delta == 0) return '亮度无变化';
    
    final change = isIncrease ? '增加' : '减少';
    final mode = autoMode ? '(自动模式)' : '(手动模式)';
    
    return '亮度${change}${delta.abs()}% $mode';
  }
}