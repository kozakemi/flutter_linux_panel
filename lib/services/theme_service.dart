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

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppThemeMode {
  light,
  dark,
  system,
}

class ThemeService extends ChangeNotifier {
  static const String _themeModeKey = 'theme_mode';
  static const AppThemeMode _defaultThemeMode = AppThemeMode.system;
  
  static ThemeService? _instance;
  static ThemeService get instance => _instance ??= ThemeService._();
  
  ThemeService._();
  
  AppThemeMode _themeMode = _defaultThemeMode;
  bool _isInitialized = false;
  
  /// 获取当前主题模式
  AppThemeMode get themeMode => _themeMode;
  
  /// 是否已初始化
  bool get isInitialized => _isInitialized;
  
  /// 获取 Material ThemeMode
  ThemeMode get materialThemeMode {
    switch (_themeMode) {
      case AppThemeMode.light:
        return ThemeMode.light;
      case AppThemeMode.dark:
        return ThemeMode.dark;
      case AppThemeMode.system:
        return ThemeMode.system;
    }
  }
  
  /// 初始化服务，加载保存的主题设置
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedMode = prefs.getInt(_themeModeKey);
      
      if (savedMode != null && savedMode >= 0 && savedMode < AppThemeMode.values.length) {
        _themeMode = AppThemeMode.values[savedMode];
      } else {
        _themeMode = _defaultThemeMode;
      }
      
      _isInitialized = true;
      print('ThemeService: 已加载主题设置 - $_themeMode');
      notifyListeners();
    } catch (e) {
      print('ThemeService: 初始化失败 - $e');
      _themeMode = _defaultThemeMode;
      _isInitialized = true;
      notifyListeners();
    }
  }
  
  /// 设置主题模式
  Future<void> setThemeMode(AppThemeMode mode) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_themeModeKey, mode.index);
      
      _themeMode = mode;
      print('ThemeService: 主题设置已更新 - $_themeMode');
      notifyListeners();
    } catch (e) {
      print('ThemeService: 保存主题设置失败 - $e');
      throw Exception('保存主题设置失败: $e');
    }
  }
  
  /// 重置为默认主题模式
  Future<void> resetThemeMode() async {
    await setThemeMode(_defaultThemeMode);
  }
  
  /// 获取主题模式显示名称
  String getThemeModeName(AppThemeMode mode) {
    switch (mode) {
      case AppThemeMode.light:
        return '浅色';
      case AppThemeMode.dark:
        return '深色';
      case AppThemeMode.system:
        return '跟随系统';
    }
  }
}
