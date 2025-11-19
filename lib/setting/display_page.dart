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
import '../services/display_service.dart';
import '../services/websocket_service_manager.dart';
import '../services/brightness_module.dart';
import '../models/brightness_models.dart';
import '../services/display_service.dart';

class DisplaySettingsPage extends StatefulWidget {
  const DisplaySettingsPage({super.key});

  @override
  State<DisplaySettingsPage> createState() => _DisplaySettingsPageState();
}

class _DisplaySettingsPageState extends State<DisplaySettingsPage> {
  static const String _scaleFactorKey = 'display_scale_factor';

  // 4档缩放比例：100%, 125%, 150%, 175%, 200%
  static const List<double> _scaleValues = [1.0, 1.25, 1.50, 1.75, 2.0];
  static const List<String> _scaleLabels = [
    '100%',
    '125%',
    '150%',
    '175%',
    '200%'
  ];

  double _currentScale = 1.0;
  int _currentIndex = 0;
  bool _isLoading = true;

  // 亮度相关状态
  BrightnessStatus _brightnessStatus = BrightnessStatus(
    current: 50,
    max: 100,
    autoEnabled: false,
    available: false,
  );
  bool _brightnessLoading = true;
  String _brightnessError = '';

  // 亮度模块
  BrightnessModule? _brightnessModule;

  @override
  void initState() {
    super.initState();
    _loadScale();
    _initBrightnessModule();
  }

  @override
  void dispose() {
    // 亮度模块由 WebSocketServiceManager 管理，无需手动释放
    super.dispose();
  }

  /// 加载保存的缩放比例
  Future<void> _loadScale() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedScale = prefs.getDouble(_scaleFactorKey) ?? 1.0;

      // 找到最接近的档位
      int index = 0;
      double minDiff = double.infinity;
      for (int i = 0; i < _scaleValues.length; i++) {
        final diff = (savedScale - _scaleValues[i]).abs();
        if (diff < minDiff) {
          minDiff = diff;
          index = i;
        }
      }

      setState(() {
        _currentScale = _scaleValues[index];
        _currentIndex = index;
        _isLoading = false;
      });
    } catch (e) {
      print('加载缩放设置失败: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  /// 保存缩放比例
  Future<void> _saveScaleFactor(double scale) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_scaleFactorKey, scale);
      print('缩放设置已保存: $scale');
    } catch (e) {
      print('保存缩放设置失败: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('保存设置失败')),
        );
      }
    }
  }

  /// 更新缩放比例
  void _updateScale(int index) async {
    if (index >= 0 && index < _scaleValues.length) {
      final newScale = _scaleValues[index];
      setState(() {
        _currentScale = newScale;
        _currentIndex = index;
      });

      try {
        // 使用DisplayService更新全局缩放
        await DisplayService.instance.setScaleFactor(newScale);
        await _saveScaleFactor(newScale);

        // 显示提示信息
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('界面缩放已设置为 ${_scaleLabels[index]}'),
              duration: const Duration(milliseconds: 1200),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('设置失败: $e')),
          );
        }
      }
    }
  }

  /// 初始化亮度模块
  Future<void> _initBrightnessModule() async {
    try {
      // 获取亮度模块实例
      _brightnessModule = WebSocketServiceManager.instance.brightnessModule;

      if (_brightnessModule == null) {
        throw Exception('无法获取亮度模块');
      }

      // 监听亮度状态变化
      _brightnessModule!.statusStream.listen((status) {
        if (mounted) {
          setState(() {
            _brightnessStatus = status;
            _brightnessLoading = false;
            _brightnessError = '';
          });
        }
      });

      // 监听调节状态变化
      _brightnessModule!.adjustingStream.listen((isAdjusting) {
        // 可以在这里添加调节状态的UI反馈
      });

      // 获取初始状态
      await _brightnessModule!.getStatus();
    } catch (e) {
      if (mounted) {
        setState(() {
          _brightnessError = '初始化失败: $e';
          _brightnessLoading = false;
        });
      }
    }
  }

  /// 设置亮度
  Future<void> _setBrightness(int brightness) async {
    if (_brightnessModule != null) {
      await _brightnessModule!.setBrightness(brightness);
    }
  }

  /// 设置自动亮度
  Future<void> _setAutoBrightness(bool enable) async {
    if (_brightnessModule != null) {
      await _brightnessModule!.setAutoMode(enable);
    }
  }

  /// 构建亮度调节部分
  Widget _buildBrightnessSection() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          // 亮度滑块
          ListTile(
            title: const Text('屏幕亮度'),
            subtitle: _brightnessLoading
                ? const Text('加载中...')
                : _brightnessError.isNotEmpty
                    ? Text(_brightnessError,
                        style: const TextStyle(color: Colors.red))
                    : Text('当前: ${_brightnessStatus.percentage}%'),
            trailing: _brightnessLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(
                    '${_brightnessStatus.percentage}%',
                    style: TextStyle(
                      color: Theme.of(context).primaryColor,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
          ),
          if (!_brightnessLoading && _brightnessError.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Column(
                children: [
                  Row(
                    children: [
                      Icon(Icons.brightness_low,
                          color: Colors.grey[600], size: 20),
                      Expanded(
                        child: Slider(
                          value: _brightnessStatus.percentage.toDouble(),
                          min: 0,
                          max: 100,
                          divisions: 30,
                          onChanged: _brightnessStatus.autoEnabled
                              ? null
                              : (value) {
                                  _setBrightness(value.round());
                                },
                        ),
                      ),
                      Icon(Icons.brightness_high,
                          color: Colors.grey[600], size: 20),
                    ],
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('0%',
                          style:
                              TextStyle(fontSize: 12, color: Colors.grey[600])),
                      Text('25%',
                          style:
                              TextStyle(fontSize: 12, color: Colors.grey[600])),
                      Text('50%',
                          style:
                              TextStyle(fontSize: 12, color: Colors.grey[600])),
                      Text('75%',
                          style:
                              TextStyle(fontSize: 12, color: Colors.grey[600])),
                      Text('100%',
                          style:
                              TextStyle(fontSize: 12, color: Colors.grey[600])),
                    ],
                  ),
                ],
              ),
            ),
          // 自动亮度开关
          // if (!_brightnessLoading && _brightnessError.isEmpty)
          //   ListTile(
          //     title: const Text('自动亮度'),
          //     subtitle: const Text('根据环境光线自动调节屏幕亮度'),
          //     trailing: Switch(
          //       value: _brightnessStatus.autoEnabled,
          //       onChanged: _setAutoBrightness,
          //     ),
          //   ),
        ],
      ),
    );
  }

  /// 构建节标题
  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: Colors.grey,
        ),
      ),
    );
  }

  /// 构建预览区域
  Widget _buildPreviewSection() {
    return Transform.scale(
      scale: _currentScale,
      child: Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey[300]!),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '预览效果',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Icon(Icons.home, color: Colors.blue[600]),
                Icon(Icons.settings, color: Colors.grey[600]),
                Icon(Icons.wifi, color: Colors.green[600]),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              '这是界面缩放的预览效果',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scale = DisplayService.instance.scaleFactor;
    final iconSize = 24.0 * scale;
    final toolbarHeight = 56.0 * scale;
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('显示设置'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        toolbarHeight: toolbarHeight,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          iconSize: iconSize,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                _sectionHeader('界面缩放'),
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    children: [
                      ListTile(
                        title: const Text('缩放比例'),
                        subtitle: Text('当前: ${_scaleLabels[_currentIndex]}'),
                        trailing: Text(
                          _scaleLabels[_currentIndex],
                          style: TextStyle(
                            color: Theme.of(context).primaryColor,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        child: Column(
                          children: [
                            Slider(
                              value: _currentIndex.toDouble(),
                              min: 0,
                              max: (_scaleValues.length - 1).toDouble(),
                              divisions: _scaleValues.length - 1,
                              onChanged: (value) {
                                _updateScale(value.round());
                              },
                            ),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: _scaleLabels.map((label) {
                                return Text(
                                  label,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[600],
                                  ),
                                );
                              }).toList(),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                _sectionHeader('屏幕亮度'),
                _buildBrightnessSection(),
                // _sectionHeader('预览'),
                // _buildPreviewSection(),
                // Container(
                //   margin: const EdgeInsets.all(16),
                //   padding: const EdgeInsets.all(16),
                //   decoration: BoxDecoration(
                //     color: Colors.blue[50],
                //     borderRadius: BorderRadius.circular(8),
                //     border: Border.all(color: Colors.blue[200]!),
                //   ),
                //   child: Column(
                //     crossAxisAlignment: CrossAxisAlignment.start,
                //     children: [
                //       Row(
                //         children: [
                //           Icon(Icons.info_outline,
                //               color: Colors.blue[600], size: 20),
                //           const SizedBox(width: 8),
                //           Text(
                //             '使用说明',
                //             style: TextStyle(
                //               fontWeight: FontWeight.w500,
                //               color: Colors.blue[800],
                //             ),
                //           ),
                //         ],
                //       ),
                //       const SizedBox(height: 8),
                //       Text(
                //         '• 调整界面缩放比例以适应不同的屏幕尺寸\n'
                //         '• 设置会自动保存并在下次启动时生效\n'
                //         '• 建议根据屏幕大小选择合适的缩放比例',
                //         style: TextStyle(
                //           fontSize: 12,
                //           color: Colors.blue[700],
                //           height: 1.4,
                //         ),
                //       ),
                //     ],
                //   ),
                // ),
              ],
            ),
    );
  }
}
