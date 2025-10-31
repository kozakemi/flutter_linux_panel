import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DisplayService extends ChangeNotifier {
  static const String _scaleFactorKey = 'display_scale_factor';
  static const double _defaultScale = 1.0;
  
  static DisplayService? _instance;
  static DisplayService get instance => _instance ??= DisplayService._();
  
  DisplayService._();
  
  double _scaleFactor = _defaultScale;
  bool _isInitialized = false;
  
  /// 获取当前缩放比例
  double get scaleFactor => _scaleFactor;
  
  /// 是否已初始化
  bool get isInitialized => _isInitialized;
  
  /// 初始化服务，加载保存的缩放设置
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      final prefs = await SharedPreferences.getInstance();
      _scaleFactor = prefs.getDouble(_scaleFactorKey) ?? _defaultScale;
      _isInitialized = true;
      
      print('DisplayService: 已加载缩放设置 - $_scaleFactor');
      notifyListeners();
    } catch (e) {
      print('DisplayService: 初始化失败 - $e');
      _scaleFactor = _defaultScale;
      _isInitialized = true;
      notifyListeners();
    }
  }
  
  /// 设置缩放比例
  Future<void> setScaleFactor(double scale) async {
    if (scale <= 0) return;
    
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_scaleFactorKey, scale);
      
      _scaleFactor = scale;
      print('DisplayService: 缩放设置已更新 - $_scaleFactor');
      notifyListeners();
    } catch (e) {
      print('DisplayService: 保存缩放设置失败 - $e');
      throw Exception('保存缩放设置失败: $e');
    }
  }
  
  /// 重置为默认缩放
  Future<void> resetScale() async {
    await setScaleFactor(_defaultScale);
  }
  
  /// 获取缩放后的尺寸
  double getScaledSize(double originalSize) {
    return originalSize * _scaleFactor;
  }
  
  /// 获取缩放后的EdgeInsets
  EdgeInsets getScaledPadding(EdgeInsets originalPadding) {
    return EdgeInsets.fromLTRB(
      originalPadding.left * _scaleFactor,
      originalPadding.top * _scaleFactor,
      originalPadding.right * _scaleFactor,
      originalPadding.bottom * _scaleFactor,
    );
  }
}