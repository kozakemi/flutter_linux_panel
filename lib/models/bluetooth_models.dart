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

// 蓝牙数据模型，用于 Linux BlueZ D-Bus 交互

/// 蓝牙设备类型
enum BluetoothDeviceType {
  unknown,
  phone,
  computer,
  audioVideo,
  peripheral,
  imaging,
  wearable,
  toy,
  health,
  uncategorized,
}

/// 蓝牙设备配对状态
enum BluetoothPairingState {
  notPaired,
  pairing,
  paired,
  failed,
}

/// 蓝牙连接状态
enum BluetoothConnectionState {
  disconnected,
  connecting,
  connected,
  disconnecting,
}

/// 蓝牙适配器状态
class BluetoothAdapterStatus {
  final String address;
  final String name;
  final String alias;
  final bool powered;
  final bool discoverable;
  final bool pairable;
  final bool discovering;

  const BluetoothAdapterStatus({
    required this.address,
    required this.name,
    required this.alias,
    required this.powered,
    required this.discoverable,
    required this.pairable,
    required this.discovering,
  });

  factory BluetoothAdapterStatus.empty() {
    return const BluetoothAdapterStatus(
      address: '',
      name: '',
      alias: '',
      powered: false,
      discoverable: false,
      pairable: false,
      discovering: false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'address': address,
      'name': name,
      'alias': alias,
      'powered': powered,
      'discoverable': discoverable,
      'pairable': pairable,
      'discovering': discovering,
    };
  }

  BluetoothAdapterStatus copyWith({
    String? address,
    String? name,
    String? alias,
    bool? powered,
    bool? discoverable,
    bool? pairable,
    bool? discovering,
  }) {
    return BluetoothAdapterStatus(
      address: address ?? this.address,
      name: name ?? this.name,
      alias: alias ?? this.alias,
      powered: powered ?? this.powered,
      discoverable: discoverable ?? this.discoverable,
      pairable: pairable ?? this.pairable,
      discovering: discovering ?? this.discovering,
    );
  }

  /// 获取状态描述
  String get statusDescription {
    if (!powered) return '蓝牙已关闭';
    if (discovering) return '正在扫描...';
    return '蓝牙已开启';
  }
}

/// 蓝牙设备信息
class BluetoothDevice {
  final String address;
  final String name;
  final String alias;
  final BluetoothDeviceType deviceType;
  final int rssi;
  final bool paired;
  final bool connected;
  final bool trusted;
  final bool blocked;
  final List<String> uuids;

  const BluetoothDevice({
    required this.address,
    required this.name,
    required this.alias,
    required this.deviceType,
    required this.rssi,
    required this.paired,
    required this.connected,
    required this.trusted,
    required this.blocked,
    required this.uuids,
  });

  factory BluetoothDevice.fromJson(Map<String, dynamic> json) {
    return BluetoothDevice(
      address: json['address'] as String? ?? '',
      name: json['name'] as String? ?? '',
      alias: json['alias'] as String? ?? '',
      deviceType: _parseDeviceType(json['device_type'] as String?),
      rssi: json['rssi'] as int? ?? -100,
      paired: json['paired'] as bool? ?? false,
      connected: json['connected'] as bool? ?? false,
      trusted: json['trusted'] as bool? ?? false,
      blocked: json['blocked'] as bool? ?? false,
      uuids: (json['uuids'] as List<dynamic>?)?.cast<String>() ?? [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'address': address,
      'name': name,
      'alias': alias,
      'device_type': deviceType.name,
      'rssi': rssi,
      'paired': paired,
      'connected': connected,
      'trusted': trusted,
      'blocked': blocked,
      'uuids': uuids,
    };
  }

  /// 获取显示名称（优先使用 alias，其次 name，最后 address）
  String get displayName {
    if (alias.isNotEmpty) return alias;
    if (name.isNotEmpty) return name;
    return address;
  }

  /// 获取信号强度描述
  String get signalStrength {
    if (rssi >= -50) return '优秀';
    if (rssi >= -60) return '良好';
    if (rssi >= -70) return '一般';
    if (rssi >= -80) return '较弱';
    return '很弱';
  }

  /// 信号强度百分比
  int get signalPercentage {
    // RSSI 通常范围：-100 dBm（最弱）到 -30 dBm（最强）
    if (rssi >= -30) return 100;
    if (rssi <= -100) return 0;
    return ((rssi + 100) * 100 / 70).round().clamp(0, 100);
  }

  /// 是否为 BLE 设备
  bool get isBleDevice {
    // 通过检查 GATT 相关的 UUID 来判断是否为 BLE 设备
    return uuids.any((uuid) => uuid.toLowerCase().contains('0000180'));
  }

  /// 获取设备类型图标名称
  String get iconName {
    switch (deviceType) {
      case BluetoothDeviceType.phone:
        return 'phone';
      case BluetoothDeviceType.computer:
        return 'computer';
      case BluetoothDeviceType.audioVideo:
        return 'headphones';
      case BluetoothDeviceType.peripheral:
        return 'keyboard';
      case BluetoothDeviceType.imaging:
        return 'print';
      case BluetoothDeviceType.wearable:
        return 'watch';
      case BluetoothDeviceType.toy:
        return 'toys';
      case BluetoothDeviceType.health:
        return 'favorite';
      default:
        return 'bluetooth';
    }
  }

  static BluetoothDeviceType _parseDeviceType(String? type) {
    if (type == null) return BluetoothDeviceType.unknown;
    switch (type.toLowerCase()) {
      case 'phone':
        return BluetoothDeviceType.phone;
      case 'computer':
        return BluetoothDeviceType.computer;
      case 'audio-video':
      case 'audiovideo':
        return BluetoothDeviceType.audioVideo;
      case 'peripheral':
        return BluetoothDeviceType.peripheral;
      case 'imaging':
        return BluetoothDeviceType.imaging;
      case 'wearable':
        return BluetoothDeviceType.wearable;
      case 'toy':
        return BluetoothDeviceType.toy;
      case 'health':
        return BluetoothDeviceType.health;
      default:
        return BluetoothDeviceType.unknown;
    }
  }
}

/// 蓝牙扫描结果
class BluetoothScanResult {
  final List<BluetoothDevice> devices;
  final DateTime timestamp;

  const BluetoothScanResult({
    required this.devices,
    required this.timestamp,
  });

  factory BluetoothScanResult.empty() {
    return BluetoothScanResult(
      devices: const [],
      timestamp: DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'devices': devices.map((d) => d.toJson()).toList(),
      'timestamp': timestamp.toIso8601String(),
    };
  }

  /// 按信号强度排序的设备列表
  List<BluetoothDevice> get sortedBySignal {
    final sorted = List<BluetoothDevice>.from(devices);
    sorted.sort((a, b) => b.rssi.compareTo(a.rssi));
    return sorted;
  }

  /// 已配对的设备
  List<BluetoothDevice> get pairedDevices {
    return devices.where((d) => d.paired).toList();
  }

  /// 未配对的设备
  List<BluetoothDevice> get unpairedDevices {
    return devices.where((d) => !d.paired).toList();
  }

  /// 已连接的设备
  List<BluetoothDevice> get connectedDevices {
    return devices.where((d) => d.connected).toList();
  }
}

/// BLE GATT 服务
class GattService {
  final String uuid;
  final String? name;
  final bool primary;
  final List<GattCharacteristic> characteristics;

  const GattService({
    required this.uuid,
    this.name,
    required this.primary,
    required this.characteristics,
  });

  Map<String, dynamic> toJson() {
    return {
      'uuid': uuid,
      'name': name,
      'primary': primary,
      'characteristics': characteristics.map((c) => c.toJson()).toList(),
    };
  }
}

/// BLE GATT 特性
class GattCharacteristic {
  final String uuid;
  final String? name;
  final List<String> flags; // read, write, notify, etc.
  final List<int>? value;

  const GattCharacteristic({
    required this.uuid,
    this.name,
    required this.flags,
    this.value,
  });

  Map<String, dynamic> toJson() {
    return {
      'uuid': uuid,
      'name': name,
      'flags': flags,
      'value': value,
    };
  }

  bool get canRead => flags.contains('read');
  bool get canWrite => flags.contains('write') || flags.contains('write-without-response');
  bool get canNotify => flags.contains('notify');
  bool get canIndicate => flags.contains('indicate');
}

/// 蓝牙错误类型
enum BluetoothError {
  ok(0, '成功'),
  unknown(-1, '未知错误'),
  adapterNotFound(1, '未找到蓝牙适配器'),
  adapterDisabled(2, '蓝牙已关闭'),
  deviceNotFound(3, '未找到设备'),
  connectionFailed(4, '连接失败'),
  pairingFailed(5, '配对失败'),
  pairingRejected(6, '配对被拒绝'),
  authenticationFailed(7, '认证失败'),
  timeout(8, '操作超时'),
  busy(9, '设备繁忙'),
  notConnected(10, '设备未连接'),
  notPaired(11, '设备未配对'),
  serviceNotFound(12, '服务未找到'),
  characteristicNotFound(13, '特性未找到'),
  readFailed(14, '读取失败'),
  writeFailed(15, '写入失败'),
  permissionDenied(16, '权限不足'),
  dbusError(17, 'D-Bus 错误');

  const BluetoothError(this.code, this.message);
  final int code;
  final String message;

  static BluetoothError fromCode(int code) {
    return BluetoothError.values.firstWhere(
      (e) => e.code == code,
      orElse: () => BluetoothError.unknown,
    );
  }
}
