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

import 'package:flutter/services.dart';

/// Service for communicating with the native Live2D plugin.
class Live2DService {
  static const MethodChannel _channel = MethodChannel('com.example.demo1/live2d');
  
  static Live2DService? _instance;
  
  int? _textureId;
  bool _isInitialized = false;
  bool _isRunning = false;
  
  Live2DService._();
  
  /// Get the singleton instance.
  static Live2DService get instance {
    _instance ??= Live2DService._();
    return _instance!;
  }
  
  /// Whether the service is initialized.
  bool get isInitialized => _isInitialized;
  
  /// Whether rendering is currently running.
  bool get isRunning => _isRunning;
  
  /// The texture ID to use with [Texture] widget.
  int? get textureId => _textureId;
  
  /// Initialize the Live2D renderer.
  /// 
  /// [width] and [height] specify the render target size.
  /// [modelPath] is optional path to a Live2D model.
  Future<int?> initialize({
    required int width,
    required int height,
    String? modelPath,
  }) async {
    if (_isInitialized) {
      return _textureId;
    }
    
    try {
      final result = await _channel.invokeMethod<int>('initialize', {
        'width': width,
        'height': height,
        if (modelPath != null) 'modelPath': modelPath,
      });
      
      _textureId = result;
      _isInitialized = result != null && result >= 0;
      
      return _textureId;
    } on PlatformException catch (e) {
      print('Failed to initialize Live2D: ${e.message}');
      return null;
    }
  }
  
  /// Start rendering.
  Future<bool> start() async {
    if (!_isInitialized) {
      return false;
    }
    
    try {
      final result = await _channel.invokeMethod<bool>('start');
      _isRunning = result ?? false;
      return _isRunning;
    } on PlatformException catch (e) {
      print('Failed to start Live2D: ${e.message}');
      return false;
    }
  }
  
  /// Stop rendering.
  Future<bool> stop() async {
    try {
      final result = await _channel.invokeMethod<bool>('stop');
      _isRunning = !(result ?? true);
      return result ?? false;
    } on PlatformException catch (e) {
      print('Failed to stop Live2D: ${e.message}');
      return false;
    }
  }
  
  /// Dispose the renderer and release resources.
  Future<void> dispose() async {
    try {
      await _channel.invokeMethod('dispose');
    } on PlatformException catch (e) {
      print('Failed to dispose Live2D: ${e.message}');
    }
    
    _textureId = null;
    _isInitialized = false;
    _isRunning = false;
  }
  
  /// Send touch event to the renderer.
  /// 
  /// [x] and [y] are normalized coordinates (0.0 to 1.0).
  /// [type] is "down", "move", or "up".
  Future<void> onTouch(double x, double y, String type) async {
    if (!_isInitialized) return;
    
    try {
      await _channel.invokeMethod('touch', {
        'x': x,
        'y': y,
        'type': type,
      });
    } on PlatformException catch (e) {
      print('Failed to send touch to Live2D: ${e.message}');
    }
  }
  
  /// Set the model scale.
  /// 
  /// [scale] is the scale factor (1.0 = default).
  Future<bool> setScale(double scale) async {
    if (!_isInitialized) return false;
    
    try {
      final result = await _channel.invokeMethod<bool>('setScale', {
        'scale': scale,
      });
      return result ?? false;
    } on PlatformException catch (e) {
      print('Failed to set scale: ${e.message}');
      return false;
    }
  }
  
  /// Set the model position offset.
  /// 
  /// [offsetX] and [offsetY] are the offsets (-1.0 to 1.0).
  Future<bool> setOffset(double offsetX, double offsetY) async {
    if (!_isInitialized) return false;
    
    try {
      final result = await _channel.invokeMethod<bool>('setOffset', {
        'offsetX': offsetX,
        'offsetY': offsetY,
      });
      return result ?? false;
    } on PlatformException catch (e) {
      print('Failed to set offset: ${e.message}');
      return false;
    }
  }
  
  /// Get the current model transform.
  /// 
  /// Returns a map with 'scale', 'offsetX', and 'offsetY'.
  Future<Map<String, double>?> getTransform() async {
    if (!_isInitialized) return null;
    
    try {
      final result = await _channel.invokeMethod<Map>('getTransform');
      if (result != null) {
        return {
          'scale': (result['scale'] as num?)?.toDouble() ?? 1.0,
          'offsetX': (result['offsetX'] as num?)?.toDouble() ?? 0.0,
          'offsetY': (result['offsetY'] as num?)?.toDouble() ?? 0.0,
        };
      }
      return null;
    } on PlatformException catch (e) {
      print('Failed to get transform: ${e.message}');
      return null;
    }
  }
}
