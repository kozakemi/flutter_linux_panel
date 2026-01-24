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
import 'websocket_wifi_adapter.dart';
import 'debug_service.dart';

/// WiFi 服务提供模式
enum WiFiServiceMode {
  /// 原生 D-Bus 模式
  native,
  /// WebSocket 后端模式
  websocket,
}

/// WiFi 服务提供者
/// 
/// 单例模式，管理 WiFi 服务的实例化和切换
/// 根据 DebugService 中的配置选择使用原生或 WebSocket 实现
class WiFiServiceProvider extends ChangeNotifier {
  static final WiFiServiceProvider instance = WiFiServiceProvider._();
  WiFiServiceProvider._();

  WiFiServiceInterface? _currentService;
  WiFiServiceMode _currentMode = WiFiServiceMode.native;
  bool _initialized = false;
  String? _initError;

  /// 当前使用的服务
  WiFiServiceInterface? get currentService => _currentService;

  /// 当前模式
  WiFiServiceMode get currentMode => _currentMode;

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

  /// 初始化服务提供者
  /// 
  /// 根据 DebugService 配置决定使用哪种实现
  Future<void> initialize() async {
    if (_initialized) return;

    developer.log('初始化 WiFi 服务提供者', name: 'WiFiServiceProvider');

    final useNative = DebugService.instance.useNativeWiFi;
    
    if (useNative) {
      // 优先尝试原生实现
      await _initializeNative();
    } else {
      // 使用 WebSocket 实现
      await _initializeWebSocket();
    }

    _initialized = true;
    notifyListeners();
  }

  /// 切换到原生模式
  Future<bool> switchToNative() async {
    if (_currentMode == WiFiServiceMode.native && _currentService != null) {
      return true;
    }

    developer.log('切换到原生 WiFi 服务', name: 'WiFiServiceProvider');

    // 释放当前服务
    await _currentService?.dispose();
    _currentService = null;

    // 初始化原生服务
    final success = await _initializeNative();
    notifyListeners();
    return success;
  }

  /// 切换到 WebSocket 模式
  Future<bool> switchToWebSocket() async {
    if (_currentMode == WiFiServiceMode.websocket && _currentService != null) {
      return true;
    }

    developer.log('切换到 WebSocket WiFi 服务', name: 'WiFiServiceProvider');

    // 释放当前服务
    await _currentService?.dispose();
    _currentService = null;

    // 初始化 WebSocket 服务
    final success = await _initializeWebSocket();
    notifyListeners();
    return success;
  }

  /// 初始化原生服务
  Future<bool> _initializeNative() async {
    try {
      developer.log('尝试初始化原生 WiFi 服务', name: 'WiFiServiceProvider');

      final nativeService = NativeWiFiService();
      await nativeService.initialize();

      _currentService = nativeService;
      _currentMode = WiFiServiceMode.native;
      _initError = null;

      developer.log('原生 WiFi 服务初始化成功', name: 'WiFiServiceProvider');
      return true;
    } catch (e, stackTrace) {
      developer.log(
        '原生 WiFi 服务初始化失败，回退到 WebSocket: $e',
        name: 'WiFiServiceProvider',
        error: e,
        stackTrace: stackTrace,
      );

      _initError = e.toString();

      // 回退到 WebSocket
      return await _initializeWebSocket();
    }
  }

  /// 初始化 WebSocket 服务
  Future<bool> _initializeWebSocket() async {
    try {
      developer.log('初始化 WebSocket WiFi 服务', name: 'WiFiServiceProvider');

      final wsAdapter = WebSocketWiFiAdapter();
      await wsAdapter.initialize();

      _currentService = wsAdapter;
      _currentMode = WiFiServiceMode.websocket;
      _initError = null;

      developer.log('WebSocket WiFi 服务初始化成功', name: 'WiFiServiceProvider');
      return true;
    } catch (e, stackTrace) {
      developer.log(
        'WebSocket WiFi 服务初始化失败: $e',
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
