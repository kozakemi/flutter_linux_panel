import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'theme_service.dart';

class WallpaperService extends ChangeNotifier {
  WallpaperService._();

  static final WallpaperService instance = WallpaperService._();

  static const String defaultAssetPath =
      'source/background/1622002094_B8946A9D258FB08AAF74435234C70DF7.jpg';
  static const String _wallpaperPathKey = 'wallpaper_path';

  String? _wallpaperPath;
  bool _initialized = false;

  String? get wallpaperPath => _wallpaperPath;
  bool get hasCustomWallpaper => _wallpaperPath != null;

  ImageProvider get imageProvider => _wallpaperPath == null
      ? const AssetImage(defaultAssetPath)
      : FileImage(File(_wallpaperPath!));

  Future<void> initialize() async {
    if (_initialized) return;
    final prefs = await SharedPreferences.getInstance();
    final savedPath = prefs.getString(_wallpaperPathKey);
    if (savedPath != null && await File(savedPath).exists()) {
      _wallpaperPath = savedPath;
    }
    _initialized = true;
  }

  Future<void> setWallpaper(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      throw FileSystemException('壁纸文件不存在', path);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_wallpaperPathKey, file.absolute.path);
    _wallpaperPath = file.absolute.path;
    notifyListeners();

    await ThemeService.instance.useWallpaperSeedColor(_wallpaperPath!);
  }

  Future<void> resetWallpaper() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_wallpaperPathKey);
    _wallpaperPath = null;
    notifyListeners();
    if (ThemeService.instance.useWallpaperColor) {
      await ThemeService.instance.setSeedColor(ThemeService.instance.seedColor);
    }
  }
}
