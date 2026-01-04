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
import 'services/live2d_service.dart';

class Live2DPage extends StatefulWidget {
  const Live2DPage({super.key});

  @override
  State<Live2DPage> createState() => _Live2DPageState();
}

class _Live2DPageState extends State<Live2DPage> {
  final Live2DService _live2dService = Live2DService.instance;
  bool _isLoading = true;
  String? _errorMessage;
  int? _textureId;
  
  // Render size
  static const int _renderWidth = 800;
  static const int _renderHeight = 600;
  
  // Model transform
  double _scale = 1.0;
  double _offsetX = 0.0;
  double _offsetY = 0.0;
  bool _isLocked = false;
  bool _showControls = false;
  
  // Preferences keys
  static const String _keyScale = 'live2d_scale';
  static const String _keyOffsetX = 'live2d_offset_x';
  static const String _keyOffsetY = 'live2d_offset_y';

  @override
  void initState() {
    super.initState();
    _loadSettings().then((_) => _initializeLive2D());
  }

  @override
  void dispose() {
    _live2dService.stop();
    _live2dService.dispose();
    super.dispose();
  }
  
  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _scale = prefs.getDouble(_keyScale) ?? 1.0;
        _offsetX = prefs.getDouble(_keyOffsetX) ?? 0.0;
        _offsetY = prefs.getDouble(_keyOffsetY) ?? 0.0;
      });
    } catch (e) {
      debugPrint('Failed to load settings: $e');
    }
  }
  
  Future<void> _saveSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_keyScale, _scale);
      await prefs.setDouble(_keyOffsetX, _offsetX);
      await prefs.setDouble(_keyOffsetY, _offsetY);
    } catch (e) {
      debugPrint('Failed to save settings: $e');
    }
  }
  
  void _applyTransform() {
    _live2dService.setScale(_scale);
    _live2dService.setOffset(_offsetX, _offsetY);
  }

  Future<void> _initializeLive2D() async {
    try {
      final textureId = await _live2dService.initialize(
        width: _renderWidth,
        height: _renderHeight,
      );
      
      if (textureId != null && textureId >= 0) {
        await _live2dService.start();
        
        // Apply saved transform
        _applyTransform();
        
        if (mounted) {
          setState(() {
            _textureId = textureId;
            _isLoading = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _errorMessage = '初始化失败：无法创建纹理';
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = '初始化失败: $e';
          _isLoading = false;
        });
      }
    }
  }

  void _handlePanStart(DragStartDetails details, Size size) {
    if (_isLocked) return;
    final x = details.localPosition.dx / size.width;
    final y = details.localPosition.dy / size.height;
    _live2dService.onTouch(x, y, 'down');
  }

  void _handlePanUpdate(DragUpdateDetails details, Size size) {
    if (_isLocked) return;
    final x = details.localPosition.dx / size.width;
    final y = details.localPosition.dy / size.height;
    _live2dService.onTouch(x, y, 'move');
  }

  void _handlePanEnd(DragEndDetails details) {
    if (_isLocked) return;
    _live2dService.onTouch(0, 0, 'up');
  }
  
  void _onScaleChanged(double value) {
    setState(() {
      _scale = value;
    });
    _live2dService.setScale(_scale);
  }
  
  void _onOffsetXChanged(double value) {
    setState(() {
      _offsetX = value;
    });
    _live2dService.setOffset(_offsetX, _offsetY);
  }
  
  void _onOffsetYChanged(double value) {
    setState(() {
      _offsetY = value;
    });
    _live2dService.setOffset(_offsetX, _offsetY);
  }
  
  void _resetTransform() {
    setState(() {
      _scale = 1.0;
      _offsetX = 0.0;
      _offsetY = 0.0;
    });
    _applyTransform();
    _saveSettings();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1a1a2e),
      appBar: AppBar(
        title: const Text(
          'Live2D',
          style: TextStyle(color: Colors.white),
        ),
        backgroundColor: const Color(0xFF16213e),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: Icon(
              _showControls ? Icons.tune : Icons.tune_outlined,
              color: _showControls ? const Color(0xFFe94560) : Colors.white70,
            ),
            onPressed: () {
              setState(() {
                _showControls = !_showControls;
              });
            },
            tooltip: '显示/隐藏控制面板',
          ),
          IconButton(
            icon: Icon(
              _isLocked ? Icons.lock : Icons.lock_open,
              color: _isLocked ? const Color(0xFFe94560) : Colors.white70,
            ),
            onPressed: () {
              setState(() {
                _isLocked = !_isLocked;
              });
            },
            tooltip: _isLocked ? '解锁交互' : '锁定交互',
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(
              color: Color(0xFFe94560),
            ),
            SizedBox(height: 20),
            Text(
              '正在加载 Live2D...',
              style: TextStyle(color: Colors.white70, fontSize: 16),
            ),
          ],
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.error_outline,
              color: Colors.redAccent,
              size: 64,
            ),
            const SizedBox(height: 20),
            Text(
              _errorMessage!,
              style: const TextStyle(color: Colors.white70, fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _isLoading = true;
                  _errorMessage = null;
                });
                _initializeLive2D();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFe94560),
              ),
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }

    if (_textureId == null) {
      return const Center(
        child: Text(
          '纹理未就绪',
          style: TextStyle(color: Colors.white70),
        ),
      );
    }

    return Row(
      children: [
        // Live2D Display
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return Center(
                child: GestureDetector(
                  onPanStart: (details) => _handlePanStart(details, constraints.biggest),
                  onPanUpdate: (details) => _handlePanUpdate(details, constraints.biggest),
                  onPanEnd: _handlePanEnd,
                  child: Container(
                    width: constraints.maxWidth,
                    height: constraints.maxHeight,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFe94560).withOpacity(0.2),
                          blurRadius: 20,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Texture(
                        textureId: _textureId!,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        // Control Panel
        if (_showControls)
          Container(
            width: 280,
            decoration: const BoxDecoration(
              color: Color(0xFF16213e),
              border: Border(
                left: BorderSide(
                  color: Color(0xFF0f3460),
                  width: 1,
                ),
              ),
            ),
            child: _buildControlPanel(),
          ),
      ],
    );
  }
  
  Widget _buildControlPanel() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '模型设置',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 24),
          
          // Scale slider
          _buildSliderSection(
            label: '缩放',
            value: _scale,
            min: 0.3,
            max: 3.0,
            onChanged: _onScaleChanged,
            onChangeEnd: (_) => _saveSettings(),
            displayValue: '${(_scale * 100).toInt()}%',
          ),
          const SizedBox(height: 20),
          
          // Offset X slider
          _buildSliderSection(
            label: '水平位置',
            value: _offsetX,
            min: -1.0,
            max: 1.0,
            onChanged: _onOffsetXChanged,
            onChangeEnd: (_) => _saveSettings(),
            displayValue: _offsetX.toStringAsFixed(2),
          ),
          const SizedBox(height: 20),
          
          // Offset Y slider
          _buildSliderSection(
            label: '垂直位置',
            value: _offsetY,
            min: -1.0,
            max: 1.0,
            onChanged: _onOffsetYChanged,
            onChangeEnd: (_) => _saveSettings(),
            displayValue: _offsetY.toStringAsFixed(2),
          ),
          const SizedBox(height: 32),
          
          // Lock toggle
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF0f3460),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(
                  _isLocked ? Icons.lock : Icons.lock_open,
                  color: _isLocked ? const Color(0xFFe94560) : Colors.white54,
                  size: 20,
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    '锁定交互',
                    style: TextStyle(color: Colors.white, fontSize: 14),
                  ),
                ),
                Switch(
                  value: _isLocked,
                  onChanged: (value) {
                    setState(() {
                      _isLocked = value;
                    });
                  },
                  activeColor: const Color(0xFFe94560),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          
          // Reset button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _resetTransform,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('重置设置'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0f3460),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          
          // Info section
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF0f3460).withOpacity(0.5),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: const Color(0xFFe94560).withOpacity(0.3),
                width: 1,
              ),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.info_outline, color: Color(0xFFe94560), size: 16),
                    SizedBox(width: 8),
                    Text(
                      '提示',
                      style: TextStyle(
                        color: Color(0xFFe94560),
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 8),
                Text(
                  '• 拖动模型区域可控制模型视线\n'
                  '• 缩放可调整模型大小\n'
                  '• 位置可调整模型居中偏移\n'
                  '• 锁定后禁用拖动交互',
                  style: TextStyle(
                    color: Colors.white60,
                    fontSize: 12,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildSliderSection({
    required String label,
    required double value,
    required double min,
    required double max,
    required ValueChanged<double> onChanged,
    required ValueChanged<double> onChangeEnd,
    required String displayValue,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 14,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF0f3460),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                displayValue,
                style: const TextStyle(
                  color: Color(0xFFe94560),
                  fontSize: 12,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 4,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
            activeTrackColor: const Color(0xFFe94560),
            inactiveTrackColor: const Color(0xFF0f3460),
            thumbColor: const Color(0xFFe94560),
            overlayColor: const Color(0xFFe94560).withOpacity(0.2),
          ),
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            onChanged: onChanged,
            onChangeEnd: onChangeEnd,
          ),
        ),
      ],
    );
  }
}
