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
import 'dart:io';
import 'package:dbus_wifi/dbus_wifi.dart' as dbus_wifi;
import 'package:dbus_wifi/models/wifi_network.dart' as dbus_wifi_models;
import '../models/wifi_models.dart';
import 'wifi_service_interface.dart';

/// 原生 WiFi 服务实现
///
/// 使用 dbus_wifi 包通过 D-Bus 与 NetworkManager 通信
class NativeWiFiService implements WiFiServiceInterface {
  static const String _serviceName = 'native_dbus';

  dbus_wifi.DbusWifi? _dbusWifi;
  bool _initialized = false;
  bool _wifiEnabled = false;

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
  String get serviceName => _serviceName;

  @override
  WiFiStatus? get currentStatus => _currentStatus;

  @override
  WiFiScanResult? get lastScanResult => _lastScanResult;

  @override
  bool get isScanning => _isScanning;

  @override
  bool get isConnecting => _isConnecting;

  @override
  Stream<WiFiStatus> get statusStream => _statusController.stream;

  @override
  Stream<WiFiScanResult> get scanResultStream => _scanResultController.stream;

  @override
  Stream<bool> get scanningStream => _scanningController.stream;

  @override
  Stream<bool> get connectingStream => _connectingController.stream;

  @override
  Future<void> initialize() async {
    if (_initialized) return;

    developer.log('初始化原生 WiFi 服务', name: 'NativeWiFiService');

    try {
      _dbusWifi = dbus_wifi.DbusWifi();

      // 检查是否有 WiFi 设备
      final hasDevice = await _dbusWifi!.hasWifiDevice;
      if (!hasDevice) {
        throw Exception('未找到 WiFi 设备');
      }

      _wifiEnabled = await _dbusWifi!.isWifiEnabled;
      _initialized = true;
      developer.log('原生 WiFi 服务初始化成功', name: 'NativeWiFiService');

      // 获取初始状态
      await getStatus();
    } catch (e, stackTrace) {
      developer.log(
        '原生 WiFi 服务初始化失败: $e',
        name: 'NativeWiFiService',
        error: e,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  @override
  Future<void> dispose() async {
    developer.log('释放原生 WiFi 服务资源', name: 'NativeWiFiService');

    await _dbusWifi?.close();
    _dbusWifi = null;
    _initialized = false;

    await _statusController.close();
    await _scanResultController.close();
    await _scanningController.close();
    await _connectingController.close();
  }

  @override
  Future<bool> toggleWiFi(bool enable) async {
    if (!_initialized || _dbusWifi == null) {
      developer.log('服务未初始化', name: 'NativeWiFiService');
      return false;
    }

    try {
      developer.log('切换 WiFi: $enable', name: 'NativeWiFiService');

      _wifiEnabled = await _dbusWifi!.setWifiEnabled(enable);

      // 更新状态
      await getStatus();
      return _wifiEnabled == enable;
    } catch (e, stackTrace) {
      developer.log(
        '切换 WiFi 失败: $e',
        name: 'NativeWiFiService',
        error: e,
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  @override
  Future<WiFiStatus?> getStatus() async {
    if (!_initialized || _dbusWifi == null) {
      developer.log('服务未初始化', name: 'NativeWiFiService');
      return null;
    }

    try {
      developer.log('获取 WiFi 状态', name: 'NativeWiFiService');

      _wifiEnabled = await _dbusWifi!.isWifiEnabled;
      if (!_wifiEnabled) {
        final status = const WiFiStatus(enabled: false, connected: false);
        _updateStatus(status);
        return status;
      }

      final statusResult = await _dbusWifi!.getConnectionStatus();
      final connectionStatus =
          statusResult['status'] as dbus_wifi.ConnectionStatus;
      final network = statusResult['network'] as dbus_wifi_models.WifiNetwork?;

      final isConnected =
          connectionStatus == dbus_wifi.ConnectionStatus.connected;
      final addressInfo =
          isConnected ? await _getIPv4AddressInfo() : const _IPv4AddressInfo();

      final status = WiFiStatus(
        enabled: _wifiEnabled,
        connected: isConnected,
        ssid: network?.ssid,
        bssid: network?.mac,
        interface: addressInfo.interfaceName,
        ip: addressInfo.localAddress,
        gateway: addressInfo.gateway,
        signal: network?.strength,
        security: network != null ? _mapSecurityType(network.security) : null,
      );

      _updateStatus(status);
      return status;
    } catch (e, stackTrace) {
      developer.log(
        '获取 WiFi 状态失败: $e',
        name: 'NativeWiFiService',
        error: e,
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  Future<_IPv4AddressInfo> _getIPv4AddressInfo() async {
    String? routeInterface;
    String? gateway;
    try {
      final lines = await File('/proc/net/route').readAsLines();
      for (final line in lines.skip(1)) {
        final fields = line.trim().split(RegExp(r'\s+'));
        if (fields.length < 4 || fields[1] != '00000000') continue;
        final flags = int.tryParse(fields[3], radix: 16) ?? 0;
        if ((flags & 0x1) == 0) continue;
        final interfaceName = fields[0];
        final isWireless = _isWirelessInterface(interfaceName);
        if (routeInterface == null || isWireless) {
          routeInterface = interfaceName;
          gateway = _decodeRouteAddress(fields[2]);
        }
        if (isWireless) break;
      }
    } catch (_) {
      // 没有默认路由时仍尝试从网络接口获取本机地址。
    }

    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
      includeLinkLocal: false,
    );
    NetworkInterface? selected;
    if (routeInterface != null) {
      for (final interface in interfaces) {
        if (interface.name == routeInterface) {
          selected = interface;
          break;
        }
      }
    }
    if (selected == null) {
      for (final interface in interfaces) {
        if (_isWirelessInterface(interface.name)) {
          selected = interface;
          break;
        }
      }
    }
    selected ??= interfaces.isEmpty ? null : interfaces.first;

    final localAddress = selected == null || selected.addresses.isEmpty
        ? null
        : selected.addresses.first.address;
    return _IPv4AddressInfo(
      interfaceName: selected?.name ?? routeInterface,
      localAddress: localAddress,
      gateway: gateway,
    );
  }

  String? _decodeRouteAddress(String hexadecimal) {
    final value = int.tryParse(hexadecimal, radix: 16);
    if (value == null || value == 0) return null;
    return <int>[
      value & 0xff,
      (value >> 8) & 0xff,
      (value >> 16) & 0xff,
      (value >> 24) & 0xff,
    ].join('.');
  }

  bool _isWirelessInterface(String name) {
    final lowerName = name.toLowerCase();
    return lowerName.startsWith('wlan') || lowerName.startsWith('wlp');
  }

  @override
  Future<WiFiScanResult?> scanNetworks() async {
    if (!_initialized || _dbusWifi == null) {
      developer.log('服务未初始化', name: 'NativeWiFiService');
      return null;
    }

    if (_isScanning) {
      developer.log('扫描已在进行中', name: 'NativeWiFiService');
      return _lastScanResult;
    }

    try {
      developer.log('开始扫描 WiFi 网络', name: 'NativeWiFiService');
      _updateScanningState(true);

      final networks =
          await _dbusWifi!.search(timeout: const Duration(seconds: 3));

      // 获取当前连接状态以标记已连接的网络
      final statusResult = await _dbusWifi!.getConnectionStatus();
      final connectedNetwork =
          statusResult['network'] as dbus_wifi_models.WifiNetwork?;

      // 获取已保存的网络
      final savedNetworks = await _dbusWifi!.getSavedNetworks();
      final savedSsids = savedNetworks.map((n) => n['id'] as String).toSet();

      // 转换为我们的模型
      final wifiNetworks = networks.map((n) {
        final isSaved = savedSsids.contains(n.ssid);

        // dbus_wifi 的 strength 是 0-100 的百分比，我们需要转换为 dBm
        // 近似公式: dBm ≈ (percentage / 2) - 100
        final signalDbm = (n.strength / 2 - 100).round();

        return WiFiNetwork(
          ssid: n.ssid,
          bssid: n.mac,
          signal: signalDbm,
          security: _mapSecurityType(n.security),
          channel: 0, // dbus_wifi 不提供频道信息
          frequencyMhz: 0, // dbus_wifi 不提供频率信息
          recorded: isSaved,
        );
      }).toList();

      // 按信号强度排序，已连接的排在最前
      wifiNetworks.sort((a, b) {
        // 已连接的网络排在最前
        final aConnected = connectedNetwork?.ssid == a.ssid;
        final bConnected = connectedNetwork?.ssid == b.ssid;
        if (aConnected != bConnected) {
          return aConnected ? -1 : 1;
        }
        // 已保存的网络次之
        if (a.recorded != b.recorded) {
          return a.recorded ? -1 : 1;
        }
        // 按信号强度排序（dBm 越大越强）
        return b.signal.compareTo(a.signal);
      });

      final scanResult = WiFiScanResult(networks: wifiNetworks);

      _updateScanResult(scanResult);
      developer.log('扫描完成，发现 ${wifiNetworks.length} 个网络',
          name: 'NativeWiFiService');

      return scanResult;
    } catch (e, stackTrace) {
      developer.log(
        '扫描 WiFi 网络失败: $e',
        name: 'NativeWiFiService',
        error: e,
        stackTrace: stackTrace,
      );
      return null;
    } finally {
      _updateScanningState(false);
    }
  }

  @override
  Future<bool> connectToNetwork(String ssid, {String? password}) async {
    if (!_initialized || _dbusWifi == null) {
      developer.log('服务未初始化', name: 'NativeWiFiService');
      return false;
    }

    if (_isConnecting) {
      developer.log('连接已在进行中', name: 'NativeWiFiService');
      return false;
    }

    try {
      developer.log('连接到网络: $ssid', name: 'NativeWiFiService');
      _updateConnectingState(true);

      // 先扫描找到网络
      final networks =
          await _dbusWifi!.search(timeout: const Duration(seconds: 2));
      final targetNetwork = networks.firstWhere(
        (n) => n.ssid == ssid,
        orElse: () => throw Exception('未找到网络: $ssid'),
      );

      // 连接网络
      await _dbusWifi!.connect(targetNetwork, password ?? '');

      // 等待连接完成
      await Future.delayed(const Duration(seconds: 2));

      // 更新状态
      await getStatus();

      developer.log('成功连接到: $ssid', name: 'NativeWiFiService');
      return true;
    } catch (e, stackTrace) {
      developer.log(
        '连接网络失败: $e',
        name: 'NativeWiFiService',
        error: e,
        stackTrace: stackTrace,
      );
      return false;
    } finally {
      _updateConnectingState(false);
    }
  }

  @override
  Future<bool> disconnect() async {
    if (!_initialized || _dbusWifi == null) {
      developer.log('服务未初始化', name: 'NativeWiFiService');
      return false;
    }

    try {
      developer.log('断开 WiFi 连接', name: 'NativeWiFiService');

      final result = await _dbusWifi!.disconnect();

      // 更新状态
      await getStatus();

      return result;
    } catch (e, stackTrace) {
      developer.log(
        '断开连接失败: $e',
        name: 'NativeWiFiService',
        error: e,
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  /// 映射安全类型为字符串
  String _mapSecurityType(String security) {
    switch (security.toLowerCase()) {
      case 'none':
        return '[ESS]';
      case 'wpa-psk':
        return '[WPA-PSK-CCMP][ESS]';
      case 'wpa-eap':
      case 'wpa-eap-suite-b-192':
        return '[WPA2-EAP-CCMP][ESS]';
      case 'sae':
        return '[WPA3-SAE][ESS]';
      case 'owe':
        return '[OWE][ESS]';
      default:
        return '[WPA2-PSK-CCMP][ESS]';
    }
  }

  void _updateStatus(WiFiStatus status) {
    _currentStatus = status;
    if (!_statusController.isClosed) {
      _statusController.add(status);
    }
  }

  void _updateScanResult(WiFiScanResult scanResult) {
    _lastScanResult = scanResult;
    if (!_scanResultController.isClosed) {
      _scanResultController.add(scanResult);
    }
  }

  void _updateScanningState(bool scanning) {
    _isScanning = scanning;
    if (!_scanningController.isClosed) {
      _scanningController.add(scanning);
    }
  }

  void _updateConnectingState(bool connecting) {
    _isConnecting = connecting;
    if (!_connectingController.isClosed) {
      _connectingController.add(connecting);
    }
  }
}

class _IPv4AddressInfo {
  const _IPv4AddressInfo({
    this.interfaceName,
    this.localAddress,
    this.gateway,
  });

  final String? interfaceName;
  final String? localAddress;
  final String? gateway;
}
