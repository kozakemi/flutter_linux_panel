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
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/display_service.dart';
import '../services/theme_service.dart';
import '../services/native_brightness_service.dart';
import '../models/brightness_models.dart';

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

  final NativeBrightnessService _brightnessService =
      NativeBrightnessService.instance;
  StreamSubscription<BrightnessStatus>? _brightnessSubscription;

  @override
  void initState() {
    super.initState();
    // #region debug-point B:display-page-init
    (() async {
      try {
        var debugServerUrl = 'http://198.18.0.1:7778/event';
        var debugSessionId = 'display-settings-crash';
        try {
          final env =
              await File('.dbg/display-settings-crash.env').readAsString();
          for (final line in env.split('\n')) {
            if (line.startsWith('DEBUG_SERVER_URL=')) {
              debugServerUrl = line.substring('DEBUG_SERVER_URL='.length);
            } else if (line.startsWith('DEBUG_SESSION_ID=')) {
              debugSessionId = line.substring('DEBUG_SESSION_ID='.length);
            }
          }
        } catch (_) {}
        final client = HttpClient();
        final req = await client.postUrl(Uri.parse(debugServerUrl));
        req.headers.contentType = ContentType.json;
        req.write(
          jsonEncode({
            'sessionId': debugSessionId,
            'runId': 'pre-fix',
            'hypothesisId': 'B',
            'location': 'lib/setting/display_page.dart:66',
            'msg': '[DEBUG] display page initState entered',
            'data': {
              'brightnessInitialized': _brightnessService.isInitialized,
              'currentIndex': _currentIndex,
            },
            'ts': DateTime.now().millisecondsSinceEpoch,
          }),
        );
        await req.close();
        client.close();
      } catch (_) {}
    })();
    // #endregion
    _loadScale();
    _initBrightnessModule();
  }

  @override
  void dispose() {
    _brightnessSubscription?.cancel();
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

      if (!mounted) return;
      setState(() {
        _currentIndex = index;
        _isLoading = false;
      });
    } catch (e) {
      print('加载缩放设置失败: $e');
      if (!mounted) return;
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

  /// 初始化 Flutter 亮度包。
  Future<void> _initBrightnessModule() async {
    try {
      // #region debug-point C:brightness-module-entry
      (() async {
        try {
          var debugServerUrl = 'http://198.18.0.1:7778/event';
          var debugSessionId = 'display-settings-crash';
          try {
            final env =
                await File('.dbg/display-settings-crash.env').readAsString();
            for (final line in env.split('\n')) {
              if (line.startsWith('DEBUG_SERVER_URL=')) {
                debugServerUrl = line.substring('DEBUG_SERVER_URL='.length);
              } else if (line.startsWith('DEBUG_SESSION_ID=')) {
                debugSessionId = line.substring('DEBUG_SESSION_ID='.length);
              }
            }
          } catch (_) {}
          final client = HttpClient();
          final req = await client.postUrl(Uri.parse(debugServerUrl));
          req.headers.contentType = ContentType.json;
          req.write(
            jsonEncode({
              'sessionId': debugSessionId,
              'runId': 'pre-fix',
              'hypothesisId': 'C',
              'location': 'lib/setting/display_page.dart:158',
              'msg': '[DEBUG] brightness module init entered',
              'data': {
                'serviceInitialized': _brightnessService.isInitialized,
              },
              'ts': DateTime.now().millisecondsSinceEpoch,
            }),
          );
          await req.close();
          client.close();
        } catch (_) {}
      })();
      // #endregion
      _brightnessSubscription =
          _brightnessService.statusStream.listen((status) {
        if (mounted) {
          setState(() {
            _brightnessStatus = status;
            _brightnessLoading = false;
            _brightnessError =
                status.available ? '' : '当前设备不支持亮度控制，或缺少 backlight 写入权限';
          });
        }
      });

      await _brightnessService.initialize();
      final status = await _brightnessService.getStatus();
      // #region debug-point C:brightness-module-status
      (() async {
        try {
          var debugServerUrl = 'http://198.18.0.1:7778/event';
          var debugSessionId = 'display-settings-crash';
          try {
            final env =
                await File('.dbg/display-settings-crash.env').readAsString();
            for (final line in env.split('\n')) {
              if (line.startsWith('DEBUG_SERVER_URL=')) {
                debugServerUrl = line.substring('DEBUG_SERVER_URL='.length);
              } else if (line.startsWith('DEBUG_SESSION_ID=')) {
                debugSessionId = line.substring('DEBUG_SESSION_ID='.length);
              }
            }
          } catch (_) {}
          final client = HttpClient();
          final req = await client.postUrl(Uri.parse(debugServerUrl));
          req.headers.contentType = ContentType.json;
          req.write(
            jsonEncode({
              'sessionId': debugSessionId,
              'runId': 'pre-fix',
              'hypothesisId': 'C',
              'location': 'lib/setting/display_page.dart:173',
              'msg': '[DEBUG] brightness module status fetched',
              'data': {
                'statusNull': status == null,
                'available': status?.available,
                'current': status?.current,
                'max': status?.max,
              },
              'ts': DateTime.now().millisecondsSinceEpoch,
            }),
          );
          await req.close();
          client.close();
        } catch (_) {}
      })();
      // #endregion
      if (status == null || !status.available) {
        throw Exception('当前设备不支持亮度控制，或缺少 backlight 写入权限');
      }
    } catch (e) {
      // #region debug-point C:brightness-module-error
      (() async {
        try {
          var debugServerUrl = 'http://198.18.0.1:7778/event';
          var debugSessionId = 'display-settings-crash';
          try {
            final env =
                await File('.dbg/display-settings-crash.env').readAsString();
            for (final line in env.split('\n')) {
              if (line.startsWith('DEBUG_SERVER_URL=')) {
                debugServerUrl = line.substring('DEBUG_SERVER_URL='.length);
              } else if (line.startsWith('DEBUG_SESSION_ID=')) {
                debugSessionId = line.substring('DEBUG_SESSION_ID='.length);
              }
            }
          } catch (_) {}
          final client = HttpClient();
          final req = await client.postUrl(Uri.parse(debugServerUrl));
          req.headers.contentType = ContentType.json;
          req.write(
            jsonEncode({
              'sessionId': debugSessionId,
              'runId': 'pre-fix',
              'hypothesisId': 'C',
              'location': 'lib/setting/display_page.dart:184',
              'msg': '[DEBUG] brightness module init failed',
              'data': {'error': e.toString()},
              'ts': DateTime.now().millisecondsSinceEpoch,
            }),
          );
          await req.close();
          client.close();
        } catch (_) {}
      })();
      // #endregion
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
    final success = await _brightnessService.setBrightness(brightness);
    if (!success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('设置亮度失败，请检查 backlight 权限')),
      );
    }
  }

  /// 构建亮度调节部分
  Widget _buildBrightnessSection() {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
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
          if (!_brightnessLoading &&
              _brightnessError.isEmpty &&
              _brightnessStatus.available)
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
                          onChanged: (value) {
                            setState(() {
                              _brightnessStatus = _brightnessStatus.copyWith(
                                current: value.round(),
                                max: 100,
                              );
                            });
                          },
                          onChangeEnd: (value) => _setBrightness(value.round()),
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

  /// 显示主题模式选择对话框
  void _showThemeModeDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return ListenableBuilder(
          listenable: ThemeService.instance,
          builder: (context, child) {
            final currentMode = ThemeService.instance.themeMode;
            return AlertDialog(
              title: const Text('选择主题模式'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppThemeMode.light,
                  AppThemeMode.dark,
                  AppThemeMode.system,
                ].map((mode) {
                  return RadioListTile<AppThemeMode>(
                    title: Text(ThemeService.instance.getThemeModeName(mode)),
                    value: mode,
                    groupValue: currentMode,
                    onChanged: (AppThemeMode? value) async {
                      if (value != null) {
                        await ThemeService.instance.setThemeMode(value);
                        if (context.mounted) {
                          Navigator.of(context).pop();
                        }
                      }
                    },
                  );
                }).toList(),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('取消'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// 构建节标题
  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: Colors.grey.shade600,
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
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('显示设置'),
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
                const SizedBox(height: 8),
                _sectionHeader('主题'),
                Card(
                  margin:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: ListTile(
                    leading: const Icon(Icons.brightness_6, size: 24),
                    title: const Text('主题模式'),
                    trailing: ListenableBuilder(
                      listenable: ThemeService.instance,
                      builder: (context, child) {
                        final currentMode = ThemeService.instance.themeMode;
                        return Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              ThemeService.instance
                                  .getThemeModeName(currentMode),
                              style: TextStyle(
                                color: Colors.grey.shade600,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Icon(Icons.chevron_right, size: 20),
                          ],
                        );
                      },
                    ),
                    onTap: () => _showThemeModeDialog(),
                  ),
                ),
                const SizedBox(height: 24),
                _sectionHeader('界面缩放'),
                Card(
                  margin:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  clipBehavior: Clip.antiAlias,
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
