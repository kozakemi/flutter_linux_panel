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

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppThemeMode {
  light,
  dark,
  system,
}

class ThemeService extends ChangeNotifier {
  static const String _themeModeKey = 'theme_mode';
  static const String _seedColorKey = 'theme_seed_color';
  static const String _useWallpaperColorKey = 'theme_use_wallpaper_color';
  static const AppThemeMode _defaultThemeMode = AppThemeMode.system;
  static const Color _defaultSeedColor = Colors.blue;

  static ThemeService? _instance;
  static ThemeService get instance => _instance ??= ThemeService._();

  ThemeService._();

  AppThemeMode _themeMode = _defaultThemeMode;
  Color _seedColor = _defaultSeedColor;
  bool _useWallpaperColor = false;
  bool _isInitialized = false;

  /// 获取当前主题模式
  AppThemeMode get themeMode => _themeMode;
  Color get seedColor => _seedColor;
  bool get useWallpaperColor => _useWallpaperColor;

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
      final savedSeedColor = prefs.getInt(_seedColorKey);
      _useWallpaperColor = prefs.getBool(_useWallpaperColorKey) ?? false;

      if (savedMode != null &&
          savedMode >= 0 &&
          savedMode < AppThemeMode.values.length) {
        _themeMode = AppThemeMode.values[savedMode];
      } else {
        _themeMode = _defaultThemeMode;
      }
      if (savedSeedColor != null) {
        _seedColor = Color(savedSeedColor);
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

  Future<void> setSeedColor(Color color) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_seedColorKey, color.toARGB32());
    await prefs.setBool(_useWallpaperColorKey, false);
    _seedColor = color;
    _useWallpaperColor = false;
    notifyListeners();
  }

  Future<void> useWallpaperSeedColor(String wallpaperPath) async {
    await extractColorFromWallpaper(wallpaperPath);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_useWallpaperColorKey, true);
    _useWallpaperColor = true;
    notifyListeners();
  }

  Future<void> extractColorFromWallpaper(String wallpaperPath) async {
    final color = await _extractDominantColor(File(wallpaperPath));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_seedColorKey, color.toARGB32());
    _seedColor = color;
    notifyListeners();
  }

  Future<Color> _extractDominantColor(File file) async {
    final bytes = await file.readAsBytes();
    final codec = await ui.instantiateImageCodec(
      bytes,
      targetWidth: 64,
      targetHeight: 64,
    );
    final frame = await codec.getNextFrame();
    final byteData = await frame.image.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    );
    frame.image.dispose();
    codec.dispose();
    if (byteData == null) return _defaultSeedColor;

    final pixels = byteData.buffer.asUint8List();
    final buckets = <int, int>{};
    for (var offset = 0; offset + 3 < pixels.length; offset += 4) {
      if (pixels[offset + 3] < 180) continue;
      final red = pixels[offset];
      final green = pixels[offset + 1];
      final blue = pixels[offset + 2];
      final maxChannel = _max3(red, green, blue);
      final minChannel = _min3(red, green, blue);
      final chroma = maxChannel - minChannel;
      if (maxChannel < 35 || minChannel > 225 || chroma < 12) continue;
      final key = ((red >> 3) << 10) | ((green >> 3) << 5) | (blue >> 3);
      buckets[key] = (buckets[key] ?? 0) + 24 + chroma;
    }
    if (buckets.isEmpty) return _defaultSeedColor;

    final bestKey =
        buckets.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
    return Color.fromARGB(
      255,
      (((bestKey >> 10) & 31) << 3) + 4,
      (((bestKey >> 5) & 31) << 3) + 4,
      ((bestKey & 31) << 3) + 4,
    );
  }

  int _max3(int a, int b, int c) {
    final ab = a > b ? a : b;
    return ab > c ? ab : c;
  }

  int _min3(int a, int b, int c) {
    final ab = a < b ? a : b;
    return ab < c ? ab : c;
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
