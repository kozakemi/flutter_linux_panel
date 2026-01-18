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

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 调试服务 - 管理全局调试选项状态
class DebugService extends ChangeNotifier {
  static final DebugService instance = DebugService._();
  DebugService._();

  static const String _keyPerformanceOverlay = 'debug_performance_overlay';

  bool _performanceOverlayEnabled = false;

  /// 是否启用性能监控浮窗
  bool get performanceOverlayEnabled => _performanceOverlayEnabled;

  /// 初始化调试服务
  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    _performanceOverlayEnabled = prefs.getBool(_keyPerformanceOverlay) ?? false;
    notifyListeners();
  }

  /// 设置性能监控浮窗启用状态
  Future<void> setPerformanceOverlayEnabled(bool enabled) async {
    if (_performanceOverlayEnabled == enabled) return;
    _performanceOverlayEnabled = enabled;
    notifyListeners();
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyPerformanceOverlay, enabled);
  }

  /// 切换性能监控浮窗状态
  Future<void> togglePerformanceOverlay() async {
    await setPerformanceOverlayEnabled(!_performanceOverlayEnabled);
  }
}
