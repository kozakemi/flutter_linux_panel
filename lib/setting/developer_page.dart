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
import 'package:virtual_keyboard_multi_language/virtual_keyboard_multi_language.dart';
import '../services/display_service.dart';
import '../services/debug_service.dart';
import '../services/websocket_config.dart';
import '../services/websocket_service_manager.dart';

class DeveloperPage extends StatefulWidget {
  const DeveloperPage({super.key});

  @override
  State<DeveloperPage> createState() => _DeveloperPageState();
}

class _DeveloperPageState extends State<DeveloperPage> {
  String _websocketAddress = '';
  bool _isLoadingAddress = true;
  final TextEditingController _addressController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadWebSocketAddress();
  }

  @override
  void dispose() {
    _addressController.dispose();
    super.dispose();
  }

  /// 加载保存的 WebSocket 地址
  Future<void> _loadWebSocketAddress() async {
    try {
      final address = await WebSocketConfig.getServerAddress();
      setState(() {
        _websocketAddress = address;
        _addressController.text = address;
        _isLoadingAddress = false;
      });
    } catch (e) {
      setState(() {
        _websocketAddress = WebSocketConfig.defaultServerAddress;
        _addressController.text = _websocketAddress;
        _isLoadingAddress = false;
      });
    }
  }

  /// 保存 WebSocket 地址并重启服务
  Future<void> _saveWebSocketAddress(String address) async {
    try {
      await WebSocketConfig.setServerAddress(address);
      setState(() {
        _websocketAddress = address;
      });

      // 重启 WebSocket 服务以应用新地址
      try {
        await WebSocketServiceManager.instance.restart();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('WebSocket 地址已更新为: $address'),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('地址已保存，但重启服务失败: $e'),
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('保存地址失败: $e'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  /// 显示 WebSocket 地址设置对话框
  Future<void> _showWebSocketAddressDialog() async {
    final TextEditingController addressController = TextEditingController(text: _websocketAddress);
    final FocusNode addressFocusNode = FocusNode();

    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        String inputAddress = _websocketAddress;
        bool isValidating = false;

        WidgetsBinding.instance.addPostFrameCallback((_) {
          addressFocusNode.requestFocus();
        });

        bool isValidAddress(String address) {
          if (address.isEmpty) return false;
          final parts = address.split(':');
          if (parts.length != 2) return false;
          final port = int.tryParse(parts[1]);
          return port != null && port > 0 && port < 65536;
        }

        Future<void> submit() async {
          if (!isValidAddress(inputAddress)) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('地址格式不正确，应为 host:port')),
            );
            return;
          }

          Navigator.of(ctx).pop(inputAddress);
        }

        const keyboardHeight = 300.0;
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: SafeArea(
            child: AnimatedSize(
              duration: const Duration(milliseconds: 200),
              child: Container(
                color: Colors.white,
                child: StatefulBuilder(
                  builder: (BuildContext context, StateSetter setModalState) {
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '设置 WebSocket 后端地址',
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.close),
                                onPressed: () => Navigator.of(ctx).pop(),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: TextField(
                            readOnly: true,
                            autofocus: true,
                            showCursor: true,
                            enableInteractiveSelection: false,
                            focusNode: addressFocusNode,
                            onTapOutside: (_) => addressFocusNode.requestFocus(),
                            decoration: const InputDecoration(
                              labelText: '服务器地址',
                              hintText: 'localhost:8080',
                              helperText: '格式: host:port (例如: localhost:8080)',
                              border: OutlineInputBorder(),
                            ),
                            controller: addressController,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Text(
                            '默认地址: ${WebSocketConfig.defaultServerAddress}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          height: keyboardHeight,
                          child: Container(
                            color: const Color(0xFF222222),
                            child: Focus(
                              canRequestFocus: false,
                              skipTraversal: true,
                              child: VirtualKeyboard(
                                height: keyboardHeight,
                                textColor: Colors.white,
                                defaultLayouts: const [
                                  VirtualKeyboardDefaultLayouts.English,
                                ],
                                type: VirtualKeyboardType.Alphanumeric,
                                postKeyPress: (key) {
                                  setModalState(() {
                                    switch (key.keyType) {
                                      case VirtualKeyboardKeyType.String:
                                        inputAddress += key.text ?? '';
                                        break;
                                      case VirtualKeyboardKeyType.Action:
                                        final action = key.action;
                                        if (action == null) break;
                                        switch (action) {
                                          case VirtualKeyboardKeyAction.Backspace:
                                            if (inputAddress.isNotEmpty) {
                                              inputAddress = inputAddress.substring(
                                                0,
                                                inputAddress.length - 1,
                                              );
                                            }
                                            break;
                                          case VirtualKeyboardKeyAction.Space:
                                            inputAddress += ' ';
                                            break;
                                          case VirtualKeyboardKeyAction.Return:
                                            if (isValidating) break;
                                            submit();
                                            break;
                                          case VirtualKeyboardKeyAction.Shift:
                                            break;
                                          default:
                                            break;
                                        }
                                        break;
                                    }
                                    addressController.text = inputAddress;
                                    addressFocusNode.requestFocus();
                                  });
                                },
                              ),
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                          child: Row(
                            children: [
                              Expanded(
                                child: ElevatedButton(
                                  onPressed: isValidating ? null : submit,
                                  child: isValidating
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(strokeWidth: 2),
                                        )
                                      : const Text('确定'),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
    ).whenComplete(() {
      addressController.dispose();
      addressFocusNode.dispose();
    });

    if (result != null && result.isNotEmpty) {
      await _saveWebSocketAddress(result);
    }
  }

  Widget _icon(IconData iconData) {
    return Icon(
      iconData,
      size: 24,
    );
  }

  Widget _section(List<Widget> tiles) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: ListTile.divideTiles(
          context: context,
          tiles: tiles,
          color: Theme.of(context).dividerColor.withOpacity(0.1),
        ).toList(),
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title,
        style: TextStyle(
          color: Colors.grey.shade600,
          fontSize: 13,
          fontWeight: FontWeight.w500,
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
        title: const Text('开发者选项'),
        toolbarHeight: toolbarHeight,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          iconSize: iconSize,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: ListenableBuilder(
        listenable: DebugService.instance,
        builder: (context, _) {
          final performanceOverlayEnabled = DebugService.instance.performanceOverlayEnabled;
          
          return ListView(
            children: [
              const SizedBox(height: 8),
              _sectionHeader('性能监控'),
              _section([
                SwitchListTile(
                  secondary: _icon(Icons.speed),
                  title: const Text('性能监控浮窗'),
                  subtitle: const Text('显示帧率、内存占用等信息'),
                  value: performanceOverlayEnabled,
                  onChanged: (value) {
                    DebugService.instance.setPerformanceOverlayEnabled(value);
                  },
                ),
              ]),
              const SizedBox(height: 16),
              _sectionHeader('网络设置'),
              _section([
                ListTile(
                  leading: _icon(Icons.settings_ethernet),
                  title: const Text('WebSocket 后端地址'),
                  subtitle: _isLoadingAddress
                      ? const Text('加载中...')
                      : Text('当前: $_websocketAddress'),
                  trailing: const Icon(Icons.chevron_right, size: 20),
                  onTap: _showWebSocketAddressDialog,
                ),
              ]),
              const SizedBox(height: 16),
              _sectionHeader('调试工具'),
              _section([
                ListTile(
                  leading: _icon(Icons.touch_app),
                  title: const Text('触摸屏测试'),
                  subtitle: const Text('测试触摸坐标和滑动轨迹'),
                  trailing: const Icon(Icons.chevron_right, size: 20),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const TouchTestPage()),
                  ),
                ),
              ]),
              const SizedBox(height: 24),
            ],
          );
        },
      ),
    );
  }
}

/// 触摸屏测试页面
class TouchTestPage extends StatefulWidget {
  const TouchTestPage({super.key});

  @override
  State<TouchTestPage> createState() => _TouchTestPageState();
}

class _TouchTestPageState extends State<TouchTestPage> {
  // 触摸测试相关状态
  final List<Offset> _touchTrail = []; // 存储所有触摸点轨迹
  Offset? _currentTouchPoint; // 当前触摸点坐标

  void _clearTrail() {
    setState(() {
      _touchTrail.clear();
      _currentTouchPoint = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scale = DisplayService.instance.scaleFactor;
    final iconSize = 24.0 * scale;
    final toolbarHeight = 56.0 * scale;

    return Scaffold(
      appBar: AppBar(
        title: const Text('触摸屏测试'),
        toolbarHeight: toolbarHeight,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          iconSize: iconSize,
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            iconSize: iconSize,
            onPressed: _clearTrail,
            tooltip: '清除轨迹',
          ),
        ],
      ),
      body: Stack(
        children: [
          // 触摸轨迹绘制层
          Positioned.fill(
            child: CustomPaint(
              painter: TouchTrailPainter(
                trail: _touchTrail,
                currentPoint: _currentTouchPoint,
              ),
              child: GestureDetector(
                onPanStart: (details) {
                  setState(() {
                    _touchTrail.add(details.localPosition);
                    _currentTouchPoint = details.localPosition;
                  });
                },
                onPanUpdate: (details) {
                  setState(() {
                    _touchTrail.add(details.localPosition);
                    _currentTouchPoint = details.localPosition;
                  });
                },
                onPanEnd: (details) {
                  setState(() {
                    _currentTouchPoint = null;
                  });
                },
                onTapDown: (details) {
                  setState(() {
                    _touchTrail.add(details.localPosition);
                    _currentTouchPoint = details.localPosition;
                  });
                },
                onTapUp: (details) {
                  setState(() {
                    _currentTouchPoint = null;
                  });
                },
                onDoubleTap: _clearTrail,
                child: Container(color: Colors.transparent),
              ),
            ),
          ),

          // 显示当前触摸坐标的文本
          Positioned(
            top: 20,
            left: 20,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.7),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _currentTouchPoint != null
                        ? 'X: ${_currentTouchPoint!.dx.toStringAsFixed(1)}\n'
                          'Y: ${_currentTouchPoint!.dy.toStringAsFixed(1)}'
                        : 'X: --\nY: --',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 显示轨迹点数量和提示
          Positioned(
            top: 20,
            right: 20,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.7),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '轨迹点数: ${_touchTrail.length}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    '双击清除轨迹',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// 触摸轨迹绘制器
class TouchTrailPainter extends CustomPainter {
  final List<Offset> trail;
  final Offset? currentPoint;

  TouchTrailPainter({
    required this.trail,
    this.currentPoint,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (trail.isEmpty) return;

    // 绘制轨迹线
    final linePaint = Paint()
      ..color = Colors.red
      ..strokeWidth = 3.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    if (trail.length > 1) {
      final path = Path();
      path.moveTo(trail[0].dx, trail[0].dy);
      for (int i = 1; i < trail.length; i++) {
        path.lineTo(trail[i].dx, trail[i].dy);
      }
      canvas.drawPath(path, linePaint);
    }

    // 绘制所有轨迹点
    final pointPaint = Paint()
      ..color = Colors.blue
      ..style = PaintingStyle.fill;

    for (final point in trail) {
      canvas.drawCircle(point, 5.0, pointPaint);
    }

    // 高亮显示当前触摸点
    if (currentPoint != null) {
      final currentPaint = Paint()
        ..color = Colors.yellow
        ..style = PaintingStyle.fill;
      canvas.drawCircle(currentPoint!, 10.0, currentPaint);

      final borderPaint = Paint()
        ..color = Colors.orange
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;
      canvas.drawCircle(currentPoint!, 10.0, borderPaint);
    }
  }

  @override
  bool shouldRepaint(TouchTrailPainter oldDelegate) =>
      trail.length != oldDelegate.trail.length ||
      currentPoint != oldDelegate.currentPoint;
}

