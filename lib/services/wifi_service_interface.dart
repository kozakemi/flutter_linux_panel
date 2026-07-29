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

import '../models/wifi_models.dart';

/// WiFi 服务统一接口
///
/// 定义基于 D-Bus/NetworkManager 的 WiFi 管理接口。
abstract class WiFiServiceInterface {
  /// 服务名称标识
  String get serviceName;

  /// 当前 WiFi 状态
  WiFiStatus? get currentStatus;

  /// 最后一次扫描结果
  WiFiScanResult? get lastScanResult;

  /// 是否正在扫描
  bool get isScanning;

  /// 是否正在连接
  bool get isConnecting;

  /// WiFi 状态流
  Stream<WiFiStatus> get statusStream;

  /// 扫描结果流
  Stream<WiFiScanResult> get scanResultStream;

  /// 扫描状态流
  Stream<bool> get scanningStream;

  /// 连接状态流
  Stream<bool> get connectingStream;

  /// 初始化服务
  Future<void> initialize();

  /// 释放服务资源
  Future<void> dispose();

  /// 开关 WiFi
  ///
  /// [enable] true 开启，false 关闭
  /// 返回操作是否成功
  Future<bool> toggleWiFi(bool enable);

  /// 获取当前 WiFi 状态
  Future<WiFiStatus?> getStatus();

  /// 扫描可用 WiFi 网络
  Future<WiFiScanResult?> scanNetworks();

  /// 连接到指定 WiFi 网络
  ///
  /// [ssid] 网络名称
  /// [password] 可选密码
  /// 返回连接是否成功
  Future<bool> connectToNetwork(String ssid, {String? password});

  /// 断开当前 WiFi 连接
  Future<bool> disconnect();
}
