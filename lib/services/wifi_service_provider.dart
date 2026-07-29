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
import 'package:flutter/foundation.dart';
import '../models/wifi_models.dart';
import 'wifi_service_interface.dart';
import 'native_wifi_service.dart';

/// WiFi 服务提供者，固定使用 dbus_wifi 与 NetworkManager 通信。
class WiFiServiceProvider extends ChangeNotifier {
  static final WiFiServiceProvider instance = WiFiServiceProvider._();
  WiFiServiceProvider._();

  WiFiServiceInterface? _currentService;
  bool _initialized = false;
  String? _initError;

  /// 当前使用的服务
  WiFiServiceInterface? get currentService => _currentService;

  /// 是否已初始化
  bool get isInitialized => _initialized;

  /// 初始化错误信息
  String? get initError => _initError;

  /// 当前服务名称
  String get serviceName => _currentService?.serviceName ?? 'none';

  // 代理接口方法
  WiFiStatus? get currentStatus => _currentService?.currentStatus;
  WiFiScanResult? get lastScanResult => _currentService?.lastScanResult;
  bool get isScanning => _currentService?.isScanning ?? false;
  bool get isConnecting => _currentService?.isConnecting ?? false;

  Stream<WiFiStatus> get statusStream =>
      _currentService?.statusStream ?? const Stream.empty();
  Stream<WiFiScanResult> get scanResultStream =>
      _currentService?.scanResultStream ?? const Stream.empty();
  Stream<bool> get scanningStream =>
      _currentService?.scanningStream ?? const Stream.empty();
  Stream<bool> get connectingStream =>
      _currentService?.connectingStream ?? const Stream.empty();

  /// 初始化 D-Bus WiFi 服务。
  Future<void> initialize() async {
    if (_initialized) return;

    developer.log('初始化 WiFi 服务提供者', name: 'WiFiServiceProvider');
    await _initializeNative();
    _initialized = true;
    notifyListeners();
  }

  /// 初始化原生服务
  Future<bool> _initializeNative() async {
    try {
      developer.log('尝试初始化原生 WiFi 服务', name: 'WiFiServiceProvider');

      final nativeService = NativeWiFiService();
      await nativeService.initialize();

      _currentService = nativeService;
      _initError = null;

      developer.log('原生 WiFi 服务初始化成功', name: 'WiFiServiceProvider');
      return true;
    } catch (e, stackTrace) {
      developer.log(
        '原生 WiFi 服务初始化失败: $e',
        name: 'WiFiServiceProvider',
        error: e,
        stackTrace: stackTrace,
      );

      _initError = e.toString();
      return false;
    }
  }

  /// 释放资源
  @override
  void dispose() {
    developer.log('释放 WiFi 服务提供者', name: 'WiFiServiceProvider');

    _currentService?.dispose();
    _currentService = null;
    _initialized = false;
    super.dispose();
  }

  // 代理 WiFi 操作方法

  Future<bool> toggleWiFi(bool enable) async {
    if (_currentService == null) {
      developer.log('WiFi 服务未初始化', name: 'WiFiServiceProvider');
      return false;
    }
    return _currentService!.toggleWiFi(enable);
  }

  Future<WiFiStatus?> getStatus() async {
    if (_currentService == null) {
      developer.log('WiFi 服务未初始化', name: 'WiFiServiceProvider');
      return null;
    }
    return _currentService!.getStatus();
  }

  Future<WiFiScanResult?> scanNetworks() async {
    if (_currentService == null) {
      developer.log('WiFi 服务未初始化', name: 'WiFiServiceProvider');
      return null;
    }
    return _currentService!.scanNetworks();
  }

  Future<bool> connectToNetwork(String ssid, {String? password}) async {
    if (_currentService == null) {
      developer.log('WiFi 服务未初始化', name: 'WiFiServiceProvider');
      return false;
    }
    return _currentService!.connectToNetwork(ssid, password: password);
  }

  Future<bool> disconnect() async {
    if (_currentService == null) {
      developer.log('WiFi 服务未初始化', name: 'WiFiServiceProvider');
      return false;
    }
    return _currentService!.disconnect();
  }
}
