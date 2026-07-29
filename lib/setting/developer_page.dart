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

import '../services/debug_service.dart';
import '../services/display_service.dart';

class DeveloperPage extends StatelessWidget {
  const DeveloperPage({super.key});

  Widget _section(BuildContext context, List<Widget> tiles) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('开发者选项'),
        toolbarHeight: 56 * scale,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          iconSize: 24 * scale,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: ListenableBuilder(
        listenable: DebugService.instance,
        builder: (context, _) => ListView(
          children: [
            const SizedBox(height: 8),
            _sectionHeader('性能监控'),
            _section(context, [
              SwitchListTile(
                secondary: const Icon(Icons.speed),
                title: const Text('性能监控浮窗'),
                subtitle: const Text('显示帧率、内存占用等信息'),
                value: DebugService.instance.performanceOverlayEnabled,
                onChanged: DebugService.instance.setPerformanceOverlayEnabled,
              ),
            ]),
            const SizedBox(height: 16),
            _sectionHeader('调试工具'),
            _section(context, [
              ListTile(
                leading: const Icon(Icons.touch_app),
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
        ),
      ),
    );
  }
}

class TouchTestPage extends StatefulWidget {
  const TouchTestPage({super.key});

  @override
  State<TouchTestPage> createState() => _TouchTestPageState();
}

class _TouchTestPageState extends State<TouchTestPage> {
  final List<Offset> _touchTrail = [];
  Offset? _currentTouchPoint;

  void _clearTrail() {
    setState(() {
      _touchTrail.clear();
      _currentTouchPoint = null;
    });
  }

  void _addPoint(Offset point) {
    setState(() {
      _touchTrail.add(point);
      _currentTouchPoint = point;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scale = DisplayService.instance.scaleFactor;
    return Scaffold(
      appBar: AppBar(
        title: const Text('触摸屏测试'),
        toolbarHeight: 56 * scale,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          iconSize: 24 * scale,
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            iconSize: 24 * scale,
            onPressed: _clearTrail,
            tooltip: '清除轨迹',
          ),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: TouchTrailPainter(
                trail: _touchTrail,
                currentPoint: _currentTouchPoint,
              ),
              child: GestureDetector(
                onPanStart: (details) => _addPoint(details.localPosition),
                onPanUpdate: (details) => _addPoint(details.localPosition),
                onPanEnd: (_) => setState(() => _currentTouchPoint = null),
                onTapDown: (details) => _addPoint(details.localPosition),
                onTapUp: (_) => setState(() => _currentTouchPoint = null),
                onDoubleTap: _clearTrail,
                child: Container(color: Colors.transparent),
              ),
            ),
          ),
          Positioned(
            top: 20,
            left: 20,
            child: _infoCard(
              _currentTouchPoint == null
                  ? 'X: --\nY: --'
                  : 'X: ${_currentTouchPoint!.dx.toStringAsFixed(1)}\n'
                      'Y: ${_currentTouchPoint!.dy.toStringAsFixed(1)}',
              20,
            ),
          ),
          Positioned(
            top: 20,
            right: 20,
            child: _infoCard(
              '轨迹点数: ${_touchTrail.length}\n双击清除轨迹',
              14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoCard(String text, double fontSize) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.7),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: Colors.white,
          fontSize: fontSize,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class TouchTrailPainter extends CustomPainter {
  const TouchTrailPainter({required this.trail, this.currentPoint});

  final List<Offset> trail;
  final Offset? currentPoint;

  @override
  void paint(Canvas canvas, Size size) {
    if (trail.isEmpty) return;

    final linePaint = Paint()
      ..color = Colors.red
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    if (trail.length > 1) {
      final path = Path()..moveTo(trail.first.dx, trail.first.dy);
      for (final point in trail.skip(1)) {
        path.lineTo(point.dx, point.dy);
      }
      canvas.drawPath(path, linePaint);
    }

    final pointPaint = Paint()
      ..color = Colors.blue
      ..style = PaintingStyle.fill;
    for (final point in trail) {
      canvas.drawCircle(point, 5, pointPaint);
    }

    if (currentPoint != null) {
      canvas.drawCircle(
        currentPoint!,
        10,
        Paint()
          ..color = Colors.yellow
          ..style = PaintingStyle.fill,
      );
    }
  }

  @override
  bool shouldRepaint(TouchTrailPainter oldDelegate) =>
      trail.length != oldDelegate.trail.length ||
      currentPoint != oldDelegate.currentPoint;
}
