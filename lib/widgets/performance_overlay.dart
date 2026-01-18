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
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../services/debug_service.dart';

/// 性能监控浮动组件包装器
class PerformanceOverlayWrapper extends StatelessWidget {
  final Widget child;

  const PerformanceOverlayWrapper({
    super.key,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: DebugService.instance,
      builder: (context, _) {
        final enabled = DebugService.instance.performanceOverlayEnabled;
        
        if (!enabled) {
          return child;
        }
        
        return Stack(
          children: [
            child,
            const Positioned(
              left: 8,
              bottom: 8,
              child: PerformanceMonitor(),
            ),
          ],
        );
      },
    );
  }
}

/// 性能监控浮动组件
class PerformanceMonitor extends StatefulWidget {
  const PerformanceMonitor({super.key});

  @override
  State<PerformanceMonitor> createState() => _PerformanceMonitorState();
}

class _PerformanceMonitorState extends State<PerformanceMonitor> {
  // 帧率相关
  int _frameCount = 0;
  double _fps = 0;
  double _avgFrameTime = 0;
  final List<double> _frameTimes = [];
  
  // 内存相关
  int _currentMemoryMB = 0;
  int _peakMemoryMB = 0;
  
  // 定时器
  Timer? _updateTimer;
  Duration _lastFrameTime = Duration.zero;
  
  // 拖拽位置
  Offset _position = const Offset(8, 100);
  bool _isDragging = false;
  
  // 是否展开详情
  bool _isExpanded = true;

  @override
  void initState() {
    super.initState();
    _startMonitoring();
  }

  @override
  void dispose() {
    _stopMonitoring();
    super.dispose();
  }

  void _startMonitoring() {
    // 使用 SchedulerBinding 监听帧回调
    SchedulerBinding.instance.addPostFrameCallback(_onFrame);
    
    // 定时更新显示（每秒更新一次统计数据）
    _updateTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _updateStats();
    });
  }

  void _stopMonitoring() {
    _updateTimer?.cancel();
    _updateTimer = null;
  }

  void _onFrame(Duration timestamp) {
    if (!mounted) return;
    
    if (_lastFrameTime != Duration.zero) {
      final frameTime = (timestamp - _lastFrameTime).inMicroseconds / 1000.0;
      _frameTimes.add(frameTime);
      
      // 只保留最近60帧的数据
      if (_frameTimes.length > 60) {
        _frameTimes.removeAt(0);
      }
    }
    
    _lastFrameTime = timestamp;
    _frameCount++;
    
    // 继续监听下一帧
    SchedulerBinding.instance.addPostFrameCallback(_onFrame);
  }

  void _updateStats() {
    if (!mounted) return;
    
    setState(() {
      // 计算 FPS
      _fps = _frameCount.toDouble();
      _frameCount = 0;
      
      // 计算平均帧时间
      if (_frameTimes.isNotEmpty) {
        _avgFrameTime = _frameTimes.reduce((a, b) => a + b) / _frameTimes.length;
      }
      
      // 获取内存信息
      _updateMemoryInfo();
    });
  }

  void _updateMemoryInfo() {
    try {
      // 尝试获取 RSS 内存（仅 Linux/macOS）
      final processPid = pid;
      final result = Process.runSync('ps', ['-o', 'rss=', '-p', '$processPid']);
      if (result.exitCode == 0) {
        final rssKB = int.tryParse(result.stdout.toString().trim()) ?? 0;
        _currentMemoryMB = (rssKB / 1024).round();
        if (_currentMemoryMB > _peakMemoryMB) {
          _peakMemoryMB = _currentMemoryMB;
        }
      }
    } catch (_) {
      // 内存信息获取失败时忽略
    }
  }

  Color _getFpsColor(double fps) {
    if (fps >= 55) return Colors.green;
    if (fps >= 30) return Colors.orange;
    return Colors.red;
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: _position.dx,
      top: _position.dy,
      child: GestureDetector(
        onPanStart: (_) => _isDragging = true,
        onPanUpdate: (details) {
          setState(() {
            _position += details.delta;
          });
        },
        onPanEnd: (_) => _isDragging = false,
        onTap: () {
          setState(() {
            _isExpanded = !_isExpanded;
          });
        },
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.75),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: _getFpsColor(_fps).withOpacity(0.5),
                width: 1,
              ),
            ),
            child: _isExpanded ? _buildExpandedContent() : _buildCollapsedContent(),
          ),
        ),
      ),
    );
  }

  Widget _buildCollapsedContent() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.speed,
          color: _getFpsColor(_fps),
          size: 16,
        ),
        const SizedBox(width: 4),
        Text(
          '${_fps.toStringAsFixed(0)} FPS',
          style: TextStyle(
            color: _getFpsColor(_fps),
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildExpandedContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // 帧率
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.speed,
              color: _getFpsColor(_fps),
              size: 14,
            ),
            const SizedBox(width: 4),
            Text(
              'FPS: ',
              style: TextStyle(
                color: Colors.white.withOpacity(0.7),
                fontSize: 11,
              ),
            ),
            Text(
              _fps.toStringAsFixed(1),
              style: TextStyle(
                color: _getFpsColor(_fps),
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        
        // 帧时间
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.timer_outlined,
              color: Colors.cyan,
              size: 14,
            ),
            const SizedBox(width: 4),
            Text(
              '帧时间: ',
              style: TextStyle(
                color: Colors.white.withOpacity(0.7),
                fontSize: 11,
              ),
            ),
            Text(
              '${_avgFrameTime.toStringAsFixed(1)} ms',
              style: const TextStyle(
                color: Colors.cyan,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        
        // 内存占用
        if (_currentMemoryMB > 0) ...[
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.memory,
                color: Colors.purple,
                size: 14,
              ),
              const SizedBox(width: 4),
              Text(
                '内存: ',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.7),
                  fontSize: 11,
                ),
              ),
              Text(
                '$_currentMemoryMB MB',
                style: const TextStyle(
                  color: Colors.purple,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          
          // 峰值内存
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.trending_up,
                color: Colors.amber,
                size: 14,
              ),
              const SizedBox(width: 4),
              Text(
                '峰值: ',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.7),
                  fontSize: 11,
                ),
              ),
              Text(
                '$_peakMemoryMB MB',
                style: const TextStyle(
                  color: Colors.amber,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
        
        // 提示文字
        const SizedBox(height: 6),
        Text(
          '点击折叠 | 拖拽移动',
          style: TextStyle(
            color: Colors.white.withOpacity(0.4),
            fontSize: 9,
          ),
        ),
      ],
    );
  }
}
