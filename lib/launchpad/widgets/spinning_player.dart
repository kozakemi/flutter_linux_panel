import 'package:flutter/material.dart';

import '../audio_cover.dart';

class SpinningPlayer extends StatefulWidget {
  final bool playing;
  final double size;
  final String? trackPath;

  const SpinningPlayer(
      {super.key, required this.playing, this.size = 260, this.trackPath});

  @override
  State<SpinningPlayer> createState() => _SpinningPlayerState();
}

class _SpinningPlayerState extends State<SpinningPlayer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller =
        AnimationController(vsync: this, duration: const Duration(seconds: 12));
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _controller.reset();
        _controller.forward();
      }
    });
  }

  @override
  void didUpdateWidget(covariant SpinningPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.playing) {
      _controller.forward();
    } else {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    return SizedBox(
      width: size,
      height: size,
      child: Center(
        child: FutureBuilder(
          future: widget.trackPath == null
              ? Future.value(null)
              : readEmbeddedCover(widget.trackPath!),
          builder: (context, snapshot) {
            final coverBytes = snapshot.data;
            final child = (coverBytes != null)
                ? Image.memory(coverBytes, fit: BoxFit.cover)
                : ColoredBox(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    child: Center(
                      child: Icon(
                        Icons.music_note_rounded,
                        size: size * 0.42,
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                    ),
                  );
            return ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: size,
                height: size,
                child: child,
              ),
            );
          },
        ),
      ),
    );
  }
}
