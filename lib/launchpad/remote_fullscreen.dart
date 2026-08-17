import 'package:flutter/material.dart';

Route<void> remoteFullscreenRoute(Widget page) {
  return PageRouteBuilder<void>(
    transitionDuration: const Duration(milliseconds: 280),
    reverseTransitionDuration: const Duration(milliseconds: 240),
    pageBuilder: (_, __, ___) => page,
    transitionsBuilder: (_, animation, secondaryAnimation, child) {
      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(1, 0),
          end: Offset.zero,
        ).animate(
            CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
        child: child,
      );
    },
  );
}

class RemoteFullscreen extends StatefulWidget {
  const RemoteFullscreen({super.key, required this.child});

  final Widget child;

  @override
  State<RemoteFullscreen> createState() => _RemoteFullscreenState();
}

class _RemoteFullscreenState extends State<RemoteFullscreen> {
  double _distance = 0;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(child: widget.child),
        Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          width: 52,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onHorizontalDragStart: (_) => _distance = 0,
            onHorizontalDragUpdate: (details) {
              _distance += details.primaryDelta ?? 0;
            },
            onHorizontalDragEnd: (details) {
              final velocity = details.primaryVelocity ?? 0;
              if (_distance > 28 || velocity > 220) {
                Navigator.maybePop(context);
              }
              _distance = 0;
            },
            child: Align(
              alignment: Alignment.centerLeft,
              child: Container(
                width: 5,
                height: 68,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary.withAlpha(140),
                  borderRadius: const BorderRadius.horizontal(
                    right: Radius.circular(8),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
