import 'package:flutter/material.dart';
import 'package:flutter_soloud/flutter_soloud.dart';

/// Headless audio-only entry: initialize SoLoud and play immediately on start.
class AudioBootPlayer extends StatefulWidget {
  const AudioBootPlayer({super.key});

  @override
  State<AudioBootPlayer> createState() => _AudioBootPlayerState();
}

class _AudioBootPlayerState extends State<AudioBootPlayer> {
  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      debugPrint('[SoLoud] Initializing...');
      await SoLoud.instance.init();
      debugPrint('[SoLoud] Loading sine waveform');
      final source = await SoLoud.instance.loadWaveform(
        WaveForm.sin,
        false,
        1.0,
        0.0,
      );
      debugPrint('[SoLoud] Playing sine waveform');
      final handle = await SoLoud.instance.play(
        source,
        volume: 0.5,
      );
      // Keep playing for 5 seconds
      await Future.delayed(const Duration(seconds: 5));
      await SoLoud.instance.stop(handle);
      await SoLoud.instance.disposeSource(source);
      SoLoud.instance.deinit();
      debugPrint('[SoLoud] Stopped');
    } catch (e, st) {
      debugPrint('[SoLoud] Error: $e\n$st');
    }
  }

  @override
  Widget build(BuildContext context) {
    // No UI
    return const SizedBox.shrink();
  }
}