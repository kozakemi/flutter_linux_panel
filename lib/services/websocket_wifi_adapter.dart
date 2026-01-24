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
import '../models/wifi_models.dart';
import 'wifi_module.dart';
import 'wifi_service_interface.dart';
import 'websocket_service_manager.dart';

/// WebSocket WiFi 服务适配器
/// 
/// 将现有的 WiFiModule 适配到 WiFiServiceInterface 接口
class WebSocketWiFiAdapter implements WiFiServiceInterface {
  static const String _serviceName = 'websocket';

  WiFiModule? _wifiModule;
  bool _initialized = false;

  @override
  String get serviceName => _serviceName;

  @override
  WiFiStatus? get currentStatus => _wifiModule?.currentStatus;

  @override
  WiFiScanResult? get lastScanResult => _wifiModule?.lastScanResult;

  @override
  bool get isScanning => _wifiModule?.isScanning ?? false;

  @override
  bool get isConnecting => _wifiModule?.isConnecting ?? false;

  @override
  Stream<WiFiStatus> get statusStream => 
      _wifiModule?.statusStream ?? const Stream.empty();

  @override
  Stream<WiFiScanResult> get scanResultStream => 
      _wifiModule?.scanResultStream ?? const Stream.empty();

  @override
  Stream<bool> get scanningStream => 
      _wifiModule?.scanningStream ?? const Stream.empty();

  @override
  Stream<bool> get connectingStream => 
      _wifiModule?.connectingStream ?? const Stream.empty();

  @override
  Future<void> initialize() async {
    if (_initialized) return;

    developer.log('初始化 WebSocket WiFi 适配器', name: 'WebSocketWiFiAdapter');

    try {
      // 获取 WebSocketServiceManager 中的 WiFiModule
      _wifiModule = WebSocketServiceManager.instance.wifiModule;

      if (_wifiModule == null) {
        throw Exception('WiFiModule 不可用，WebSocket 服务可能未初始化');
      }

      _initialized = true;
      developer.log('WebSocket WiFi 适配器初始化成功', name: 'WebSocketWiFiAdapter');
    } catch (e, stackTrace) {
      developer.log(
        'WebSocket WiFi 适配器初始化失败: $e',
        name: 'WebSocketWiFiAdapter',
        error: e,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  @override
  Future<void> dispose() async {
    developer.log('释放 WebSocket WiFi 适配器', name: 'WebSocketWiFiAdapter');
    // WiFiModule 的生命周期由 WebSocketServiceManager 管理
    // 这里不需要释放
    _wifiModule = null;
    _initialized = false;
  }

  @override
  Future<bool> toggleWiFi(bool enable) async {
    if (_wifiModule == null) {
      developer.log('WiFiModule 未初始化', name: 'WebSocketWiFiAdapter');
      return false;
    }
    return _wifiModule!.toggleWiFi(enable);
  }

  @override
  Future<WiFiStatus?> getStatus() async {
    if (_wifiModule == null) {
      developer.log('WiFiModule 未初始化', name: 'WebSocketWiFiAdapter');
      return null;
    }
    return _wifiModule!.getStatus();
  }

  @override
  Future<WiFiScanResult?> scanNetworks() async {
    if (_wifiModule == null) {
      developer.log('WiFiModule 未初始化', name: 'WebSocketWiFiAdapter');
      return null;
    }
    return _wifiModule!.scanNetworks();
  }

  @override
  Future<bool> connectToNetwork(String ssid, {String? password}) async {
    if (_wifiModule == null) {
      developer.log('WiFiModule 未初始化', name: 'WebSocketWiFiAdapter');
      return false;
    }
    return _wifiModule!.connectToNetwork(ssid, password: password);
  }

  @override
  Future<bool> disconnect() async {
    if (_wifiModule == null) {
      developer.log('WiFiModule 未初始化', name: 'WebSocketWiFiAdapter');
      return false;
    }
    return _wifiModule!.disconnect();
  }
}
