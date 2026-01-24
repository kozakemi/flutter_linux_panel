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
import 'package:bluez/bluez.dart';
import 'package:flutter/foundation.dart';
import '../models/bluetooth_models.dart';

/// 蓝牙服务 - 基于 BlueZ D-Bus 接口
/// 提供蓝牙适配器管理、设备扫描、配对、连接等功能
class BluetoothService extends ChangeNotifier {
  static final BluetoothService _instance = BluetoothService._internal();
  static BluetoothService get instance => _instance;

  BluetoothService._internal();

  // BlueZ 客户端
  BlueZClient? _client;
  BlueZAdapter? _adapter;

  // 状态
  bool _initialized = false;
  BluetoothAdapterStatus _adapterStatus = BluetoothAdapterStatus.empty();
  final Map<String, BluetoothDevice> _devices = {};
  bool _isScanning = false;

  // 流控制器
  final StreamController<BluetoothAdapterStatus> _adapterStatusController =
      StreamController<BluetoothAdapterStatus>.broadcast();
  final StreamController<BluetoothScanResult> _scanResultController =
      StreamController<BluetoothScanResult>.broadcast();
  final StreamController<BluetoothDevice> _deviceUpdatedController =
      StreamController<BluetoothDevice>.broadcast();

  // 订阅管理
  StreamSubscription<BlueZDevice>? _deviceAddedSubscription;
  StreamSubscription<BlueZDevice>? _deviceRemovedSubscription;

  /// 适配器状态流
  Stream<BluetoothAdapterStatus> get adapterStatusStream =>
      _adapterStatusController.stream;

  /// 扫描结果流
  Stream<BluetoothScanResult> get scanResultStream =>
      _scanResultController.stream;

  /// 设备更新流
  Stream<BluetoothDevice> get deviceUpdatedStream =>
      _deviceUpdatedController.stream;

  /// 当前适配器状态
  BluetoothAdapterStatus get adapterStatus => _adapterStatus;

  /// 所有已发现的设备
  List<BluetoothDevice> get devices => _devices.values.toList();

  /// 是否正在扫描
  bool get isScanning => _isScanning;

  /// 是否已初始化
  bool get isInitialized => _initialized;

  /// 蓝牙是否已开启
  bool get isPowered => _adapterStatus.powered;

  /// 初始化蓝牙服务
  Future<void> initialize() async {
    if (_initialized) return;

    try {
      developer.log('初始化蓝牙服务...', name: 'BluetoothService');

      _client = BlueZClient();
      await _client!.connect();

      // 获取第一个适配器
      final adapters = _client!.adapters;
      if (adapters.isEmpty) {
        developer.log('未找到蓝牙适配器', name: 'BluetoothService');
        _initialized = true;
        return;
      }

      _adapter = adapters.first;
      developer.log('使用蓝牙适配器: ${_adapter!.name}', name: 'BluetoothService');

      // 更新适配器状态
      _updateAdapterStatus();

      // 监听设备添加
      _deviceAddedSubscription = _client!.deviceAdded.listen((bluezDevice) {
        developer.log('设备添加: ${bluezDevice.name} (${bluezDevice.address})', name: 'BluetoothService');
        _updateDeviceFromBluez(bluezDevice);
        _emitScanResult();
        notifyListeners();
      });

      // 监听设备移除
      _deviceRemovedSubscription = _client!.deviceRemoved.listen((bluezDevice) {
        developer.log('设备移除: ${bluezDevice.name} (${bluezDevice.address})', name: 'BluetoothService');
        _devices.remove(bluezDevice.address);
        _emitScanResult();
        notifyListeners();
      });

      // 加载已有设备
      _loadExistingDevices();

      _initialized = true;
      notifyListeners();

      developer.log('蓝牙服务初始化完成', name: 'BluetoothService');
    } catch (e, stackTrace) {
      developer.log(
        '蓝牙服务初始化失败: $e',
        name: 'BluetoothService',
        error: e,
        stackTrace: stackTrace,
      );
      _initialized = true; // 标记为已初始化，避免重复尝试
    }
  }

  /// 释放资源
  @override
  void dispose() {
    developer.log('释放蓝牙服务资源', name: 'BluetoothService');

    _deviceAddedSubscription?.cancel();
    _deviceRemovedSubscription?.cancel();

    if (_isScanning && _adapter != null) {
      try {
        _adapter!.stopDiscovery();
      } catch (_) {}
    }

    _client?.close();

    _adapterStatusController.close();
    _scanResultController.close();
    _deviceUpdatedController.close();

    _client = null;
    _adapter = null;
    _initialized = false;

    super.dispose();
  }

  /// 开关蓝牙
  Future<bool> togglePower(bool enable) async {
    if (_adapter == null) {
      developer.log('蓝牙适配器不可用', name: 'BluetoothService');
      return false;
    }

    try {
      developer.log('设置蓝牙电源: $enable', name: 'BluetoothService');
      await _adapter!.setPowered(enable);

      // 等待状态更新
      await Future.delayed(const Duration(milliseconds: 500));
      _updateAdapterStatus();

      return _adapterStatus.powered == enable;
    } catch (e, stackTrace) {
      developer.log(
        '设置蓝牙电源失败: $e',
        name: 'BluetoothService',
        error: e,
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  /// 开始扫描设备
  Future<bool> startScan({Duration? timeout}) async {
    if (_adapter == null) {
      developer.log('蓝牙适配器不可用', name: 'BluetoothService');
      return false;
    }

    if (!_adapterStatus.powered) {
      developer.log('蓝牙未开启', name: 'BluetoothService');
      return false;
    }

    if (_isScanning) {
      developer.log('扫描已在进行中', name: 'BluetoothService');
      return true;
    }

    try {
      developer.log('开始蓝牙设备扫描', name: 'BluetoothService');

      _isScanning = true;
      _updateAdapterStatus();
      notifyListeners();

      await _adapter!.startDiscovery();

      // 如果指定了超时时间，自动停止扫描
      if (timeout != null) {
        Future.delayed(timeout, () {
          if (_isScanning) {
            stopScan();
          }
        });
      }

      return true;
    } catch (e, stackTrace) {
      developer.log(
        '开始扫描失败: $e',
        name: 'BluetoothService',
        error: e,
        stackTrace: stackTrace,
      );
      _isScanning = false;
      notifyListeners();
      return false;
    }
  }

  /// 停止扫描设备
  Future<void> stopScan() async {
    if (_adapter == null || !_isScanning) return;

    try {
      developer.log('停止蓝牙设备扫描', name: 'BluetoothService');
      await _adapter!.stopDiscovery();
    } catch (e) {
      developer.log('停止扫描失败: $e', name: 'BluetoothService');
    } finally {
      _isScanning = false;
      _updateAdapterStatus();
      notifyListeners();
    }
  }

  /// 配对设备
  Future<BluetoothError> pairDevice(String address) async {
    final bluezDevice = _findBluezDevice(address);
    if (bluezDevice == null) {
      return BluetoothError.deviceNotFound;
    }

    try {
      developer.log('配对设备: $address', name: 'BluetoothService');

      if (bluezDevice.paired) {
        developer.log('设备已配对', name: 'BluetoothService');
        return BluetoothError.ok;
      }

      await bluezDevice.pair();

      // 等待配对完成
      await Future.delayed(const Duration(milliseconds: 500));
      _updateDeviceFromBluez(bluezDevice);

      return BluetoothError.ok;
    } catch (e, stackTrace) {
      developer.log(
        '配对失败: $e',
        name: 'BluetoothService',
        error: e,
        stackTrace: stackTrace,
      );
      return BluetoothError.pairingFailed;
    }
  }

  /// 取消配对
  Future<BluetoothError> unpairDevice(String address) async {
    if (_adapter == null) {
      return BluetoothError.adapterNotFound;
    }

    final bluezDevice = _findBluezDevice(address);
    if (bluezDevice == null) {
      return BluetoothError.deviceNotFound;
    }

    try {
      developer.log('取消配对: $address', name: 'BluetoothService');
      await _adapter!.removeDevice(bluezDevice);
      _devices.remove(address);
      _emitScanResult();
      notifyListeners();
      return BluetoothError.ok;
    } catch (e, stackTrace) {
      developer.log(
        '取消配对失败: $e',
        name: 'BluetoothService',
        error: e,
        stackTrace: stackTrace,
      );
      return BluetoothError.pairingFailed;
    }
  }

  /// 连接设备
  Future<BluetoothError> connectDevice(String address) async {
    final bluezDevice = _findBluezDevice(address);
    if (bluezDevice == null) {
      return BluetoothError.deviceNotFound;
    }

    try {
      developer.log('连接设备: $address', name: 'BluetoothService');

      if (bluezDevice.connected) {
        developer.log('设备已连接', name: 'BluetoothService');
        return BluetoothError.ok;
      }

      await bluezDevice.connect();

      // 等待连接完成
      await Future.delayed(const Duration(milliseconds: 500));
      _updateDeviceFromBluez(bluezDevice);

      return BluetoothError.ok;
    } catch (e, stackTrace) {
      developer.log(
        '连接失败: $e',
        name: 'BluetoothService',
        error: e,
        stackTrace: stackTrace,
      );
      return BluetoothError.connectionFailed;
    }
  }

  /// 断开连接
  Future<BluetoothError> disconnectDevice(String address) async {
    final bluezDevice = _findBluezDevice(address);
    if (bluezDevice == null) {
      return BluetoothError.deviceNotFound;
    }

    try {
      developer.log('断开设备: $address', name: 'BluetoothService');

      if (!bluezDevice.connected) {
        developer.log('设备未连接', name: 'BluetoothService');
        return BluetoothError.ok;
      }

      await bluezDevice.disconnect();

      // 等待断开完成
      await Future.delayed(const Duration(milliseconds: 500));
      _updateDeviceFromBluez(bluezDevice);

      return BluetoothError.ok;
    } catch (e, stackTrace) {
      developer.log(
        '断开失败: $e',
        name: 'BluetoothService',
        error: e,
        stackTrace: stackTrace,
      );
      return BluetoothError.connectionFailed;
    }
  }

  /// 设置设备信任状态
  Future<BluetoothError> setDeviceTrusted(String address, bool trusted) async {
    final bluezDevice = _findBluezDevice(address);
    if (bluezDevice == null) {
      return BluetoothError.deviceNotFound;
    }

    try {
      developer.log('设置设备信任: $address -> $trusted', name: 'BluetoothService');
      await bluezDevice.setTrusted(trusted);
      _updateDeviceFromBluez(bluezDevice);
      return BluetoothError.ok;
    } catch (e, stackTrace) {
      developer.log(
        '设置信任失败: $e',
        name: 'BluetoothService',
        error: e,
        stackTrace: stackTrace,
      );
      return BluetoothError.unknown;
    }
  }

  /// 发现 GATT 服务（BLE 设备）
  Future<List<GattService>> discoverServices(String address) async {
    final bluezDevice = _findBluezDevice(address);
    if (bluezDevice == null) {
      return [];
    }

    if (!bluezDevice.connected) {
      developer.log('设备未连接，无法发现服务', name: 'BluetoothService');
      return [];
    }

    try {
      developer.log('发现 GATT 服务: $address', name: 'BluetoothService');

      final services = <GattService>[];

      for (final gattService in bluezDevice.gattServices) {
        final characteristics = <GattCharacteristic>[];

        for (final gattChar in gattService.characteristics) {
          // 将 BlueZGattCharacteristicFlag 转换为字符串列表
          final flagStrings = gattChar.flags.map((f) => _flagToString(f)).toList();
          
          characteristics.add(GattCharacteristic(
            uuid: gattChar.uuid.toString(),
            name: null,
            flags: flagStrings,
            value: null,
          ));
        }

        services.add(GattService(
          uuid: gattService.uuid.toString(),
          name: null,
          primary: gattService.primary,
          characteristics: characteristics,
        ));
      }

      developer.log('发现 ${services.length} 个服务', name: 'BluetoothService');
      return services;
    } catch (e, stackTrace) {
      developer.log(
        '发现服务失败: $e',
        name: 'BluetoothService',
        error: e,
        stackTrace: stackTrace,
      );
      return [];
    }
  }

  /// 读取 GATT 特性值
  Future<List<int>?> readCharacteristic(
      String address, String serviceUuid, String charUuid) async {
    final bluezDevice = _findBluezDevice(address);
    if (bluezDevice == null) return null;

    try {
      final gattChar = _findGattCharacteristic(bluezDevice, serviceUuid, charUuid);
      if (gattChar == null) {
        developer.log('特性未找到: $charUuid', name: 'BluetoothService');
        return null;
      }

      developer.log('读取特性: $charUuid', name: 'BluetoothService');
      final value = await gattChar.readValue();
      return value;
    } catch (e, stackTrace) {
      developer.log(
        '读取特性失败: $e',
        name: 'BluetoothService',
        error: e,
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  /// 写入 GATT 特性值
  Future<bool> writeCharacteristic(
      String address, String serviceUuid, String charUuid, List<int> value) async {
    final bluezDevice = _findBluezDevice(address);
    if (bluezDevice == null) return false;

    try {
      final gattChar = _findGattCharacteristic(bluezDevice, serviceUuid, charUuid);
      if (gattChar == null) {
        developer.log('特性未找到: $charUuid', name: 'BluetoothService');
        return false;
      }

      developer.log('写入特性: $charUuid', name: 'BluetoothService');
      await gattChar.writeValue(value);
      return true;
    } catch (e, stackTrace) {
      developer.log(
        '写入特性失败: $e',
        name: 'BluetoothService',
        error: e,
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  /// 订阅 GATT 特性通知
  Stream<List<int>>? subscribeCharacteristic(
      String address, String serviceUuid, String charUuid) {
    final bluezDevice = _findBluezDevice(address);
    if (bluezDevice == null) return null;

    try {
      final gattChar = _findGattCharacteristic(bluezDevice, serviceUuid, charUuid);
      if (gattChar == null) {
        developer.log('特性未找到: $charUuid', name: 'BluetoothService');
        return null;
      }

      developer.log('订阅特性通知: $charUuid', name: 'BluetoothService');
      gattChar.startNotify();
      return gattChar.propertiesChanged.map((props) {
        if (props.contains('Value')) {
          return gattChar.value;
        }
        return <int>[];
      }).where((v) => v.isNotEmpty);
    } catch (e, stackTrace) {
      developer.log(
        '订阅特性失败: $e',
        name: 'BluetoothService',
        error: e,
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  /// 取消订阅 GATT 特性通知
  Future<void> unsubscribeCharacteristic(
      String address, String serviceUuid, String charUuid) async {
    final bluezDevice = _findBluezDevice(address);
    if (bluezDevice == null) return;

    try {
      final gattChar = _findGattCharacteristic(bluezDevice, serviceUuid, charUuid);
      if (gattChar == null) return;

      developer.log('取消订阅特性通知: $charUuid', name: 'BluetoothService');
      await gattChar.stopNotify();
    } catch (e) {
      developer.log('取消订阅失败: $e', name: 'BluetoothService');
    }
  }

  /// 获取扫描结果
  BluetoothScanResult getScanResult() {
    return BluetoothScanResult(
      devices: _devices.values.toList(),
      timestamp: DateTime.now(),
    );
  }

  // ============== 私有方法 ==============

  /// 更新适配器状态
  void _updateAdapterStatus() {
    if (_adapter == null) {
      _adapterStatus = BluetoothAdapterStatus.empty();
    } else {
      _adapterStatus = BluetoothAdapterStatus(
        address: _adapter!.address,
        name: _adapter!.name,
        alias: _adapter!.alias,
        powered: _adapter!.powered,
        discoverable: _adapter!.discoverable,
        pairable: _adapter!.pairable,
        discovering: _isScanning || _adapter!.discovering,
      );
    }

    if (!_adapterStatusController.isClosed) {
      _adapterStatusController.add(_adapterStatus);
    }
    notifyListeners();
  }

  /// 加载已有设备
  void _loadExistingDevices() {
    if (_client == null) return;

    for (final bluezDevice in _client!.devices) {
      _updateDeviceFromBluez(bluezDevice);
    }

    _emitScanResult();
  }

  /// 从 BlueZ 设备更新内部设备信息
  void _updateDeviceFromBluez(BlueZDevice bluezDevice) {
    final device = BluetoothDevice(
      address: bluezDevice.address,
      name: bluezDevice.name,
      alias: bluezDevice.alias,
      deviceType: _parseDeviceClass(bluezDevice.deviceClass),
      rssi: bluezDevice.rssi,
      paired: bluezDevice.paired,
      connected: bluezDevice.connected,
      trusted: bluezDevice.trusted,
      blocked: bluezDevice.blocked,
      uuids: bluezDevice.uuids.map((u) => u.toString()).toList(),
    );

    _devices[bluezDevice.address] = device;

    if (!_deviceUpdatedController.isClosed) {
      _deviceUpdatedController.add(device);
    }
  }

  /// 发送扫描结果
  void _emitScanResult() {
    if (!_scanResultController.isClosed) {
      _scanResultController.add(getScanResult());
    }
  }

  /// 查找 BlueZ 设备
  BlueZDevice? _findBluezDevice(String address) {
    if (_client == null) return null;

    try {
      return _client!.devices.firstWhere(
        (d) => d.address.toUpperCase() == address.toUpperCase(),
      );
    } catch (_) {
      return null;
    }
  }

  /// 查找 GATT 特性
  BlueZGattCharacteristic? _findGattCharacteristic(
      BlueZDevice device, String serviceUuid, String charUuid) {
    try {
      final service = device.gattServices.firstWhere(
        (s) => s.uuid.toString().toLowerCase() == serviceUuid.toLowerCase(),
      );
      return service.characteristics.firstWhere(
        (c) => c.uuid.toString().toLowerCase() == charUuid.toLowerCase(),
      );
    } catch (_) {
      return null;
    }
  }

  /// 解析设备类型
  BluetoothDeviceType _parseDeviceClass(int deviceClass) {
    // BlueZ 设备类是一个 24 位的值
    // 主要类型在 bits 8-12
    final majorClass = (deviceClass >> 8) & 0x1F;

    switch (majorClass) {
      case 1:
        return BluetoothDeviceType.computer;
      case 2:
        return BluetoothDeviceType.phone;
      case 3:
        return BluetoothDeviceType.unknown; // LAN/Network Access Point
      case 4:
        return BluetoothDeviceType.audioVideo;
      case 5:
        return BluetoothDeviceType.peripheral;
      case 6:
        return BluetoothDeviceType.imaging;
      case 7:
        return BluetoothDeviceType.wearable;
      case 8:
        return BluetoothDeviceType.toy;
      case 9:
        return BluetoothDeviceType.health;
      default:
        return BluetoothDeviceType.unknown;
    }
  }

  /// 将 BlueZGattCharacteristicFlag 转换为字符串
  String _flagToString(BlueZGattCharacteristicFlag flag) {
    switch (flag) {
      case BlueZGattCharacteristicFlag.broadcast:
        return 'broadcast';
      case BlueZGattCharacteristicFlag.read:
        return 'read';
      case BlueZGattCharacteristicFlag.writeWithoutResponse:
        return 'write-without-response';
      case BlueZGattCharacteristicFlag.write:
        return 'write';
      case BlueZGattCharacteristicFlag.notify:
        return 'notify';
      case BlueZGattCharacteristicFlag.indicate:
        return 'indicate';
      case BlueZGattCharacteristicFlag.authenticatedSignedWrites:
        return 'authenticated-signed-writes';
      case BlueZGattCharacteristicFlag.extendedProperties:
        return 'extended-properties';
      case BlueZGattCharacteristicFlag.reliableWrite:
        return 'reliable-write';
      case BlueZGattCharacteristicFlag.writableAuxiliaries:
        return 'writable-auxiliaries';
      case BlueZGattCharacteristicFlag.encryptRead:
        return 'encrypt-read';
      case BlueZGattCharacteristicFlag.encryptWrite:
        return 'encrypt-write';
      case BlueZGattCharacteristicFlag.encryptAuthenticatedRead:
        return 'encrypt-authenticated-read';
      case BlueZGattCharacteristicFlag.encryptAuthenticatedWrite:
        return 'encrypt-authenticated-write';
      case BlueZGattCharacteristicFlag.secureRead:
        return 'secure-read';
      case BlueZGattCharacteristicFlag.secureWrite:
        return 'secure-write';
      case BlueZGattCharacteristicFlag.authorize:
        return 'authorize';
    }
  }
}
