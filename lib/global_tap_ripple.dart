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

/// 全局点击水波纹覆盖层，捕获全局点击并在点击位置显示水波纹动效
class GlobalTapRipple extends StatefulWidget {
  final Widget child;
  final Duration duration;
  final Color color;

  const GlobalTapRipple({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 600),
    this.color = const Color(0xFFFFFFFF),
  });

  @override
  State<GlobalTapRipple> createState() => _GlobalTapRippleState();
}

class _GlobalTapRippleState extends State<GlobalTapRipple>
    with TickerProviderStateMixin {
  final List<_RippleData> _ripples = [];

  void _addRipple(Offset globalPos) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final localPos = box.globalToLocal(globalPos);
    final size = box.size;
    final maxRadius = _calcMaxRadius(localPos, size);

    final controller = AnimationController(vsync: this, duration: widget.duration);
    final radiusAnim = Tween<double>(begin: 0.0, end: maxRadius)
        .animate(CurvedAnimation(parent: controller, curve: Curves.easeOut));
    final opacityAnim = Tween<double>(begin: 0.25, end: 0.0)
        .animate(CurvedAnimation(parent: controller, curve: Curves.easeOut));

    final data = _RippleData(
      position: localPos,
      radius: radiusAnim,
      opacity: opacityAnim,
      controller: controller,
    );

    controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        controller.dispose();
        setState(() {
          _ripples.remove(data);
        });
      }
    });

    setState(() {
      _ripples.add(data);
    });
    controller.forward();
  }

  double _calcMaxRadius(Offset pos, Size size) {
    final distances = <double>[
      (pos - const Offset(0, 0)).distance,
      (pos - Offset(size.width, 0)).distance,
      (pos - Offset(0, size.height)).distance,
      (pos - Offset(size.width, size.height)).distance,
    ];
    distances.sort((a, b) => b.compareTo(a));
    return distances.first;
  }

  @override
  void dispose() {
    for (final r in _ripples) {
      r.controller.dispose();
    }
    _ripples.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (event) {
        _addRipple(event.position);
      },
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          // 原始应用内容
          widget.child,
          // 覆盖层水波纹效果；IgnorePointer 确保不影响交互
          IgnorePointer(
            ignoring: true,
            child: Stack(
              children: _ripples
                  .map((r) => AnimatedBuilder(
                        animation: r.controller,
                        builder: (context, _) {
                          final radius = r.radius.value;
                          final opacity = r.opacity.value;
                          return Positioned(
                            left: r.position.dx - radius,
                            top: r.position.dy - radius,
                            width: radius * 2,
                            height: radius * 2,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: widget.color.withOpacity(opacity),
                              ),
                            ),
                          );
                        },
                      ))
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class _RippleData {
  final Offset position;
  final Animation<double> radius;
  final Animation<double> opacity;
  final AnimationController controller;

  _RippleData({
    required this.position,
    required this.radius,
    required this.opacity,
    required this.controller,
  });
}