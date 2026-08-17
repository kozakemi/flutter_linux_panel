import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../services/remote_launchpad_service.dart';
import 'remote_fullscreen.dart';

class RemoteMediaPage extends StatefulWidget {
  const RemoteMediaPage({
    super.key,
    required this.computerId,
    required this.computerName,
  });

  final String computerId;
  final String computerName;

  @override
  State<RemoteMediaPage> createState() => _RemoteMediaPageState();
}

class _RemoteMediaPageState extends State<RemoteMediaPage> {
  String _cachedArtworkText = '';
  Uint8List? _cachedArtwork;
  double? _dragPosition;
  double? _dragVolume;

  @override
  Widget build(BuildContext context) {
    final service = RemoteLaunchpadService.instance;
    return Scaffold(
      body: RemoteFullscreen(
        child: SafeArea(
          child: AnimatedBuilder(
            animation: service,
            builder: (context, _) {
              final state = service.mediaStateForComputer(widget.computerId);
              if (!state.available) return _Unavailable(state: state);
              final artwork = _artwork(state.artworkBase64);
              final duration = state.duration > 0 ? state.duration : 1.0;
              final position = (_dragPosition ?? state.position).clamp(
                0.0,
                duration,
              );
              final volume = (_dragVolume ?? state.volume).clamp(0.0, 1.0);
              return Padding(
                padding: const EdgeInsets.fromLTRB(22, 12, 16, 12),
                child: Row(
                  children: [
                    Expanded(
                      flex: 4,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${widget.computerName} · 声音与媒体',
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                          const SizedBox(height: 8),
                          Expanded(
                            child: Center(
                              child: AspectRatio(
                                aspectRatio: 1,
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(20),
                                  child: artwork == null
                                      ? _ArtworkFallback(context: context)
                                      : Image.memory(
                                          artwork,
                                          fit: BoxFit.cover,
                                          gaplessPlayback: true,
                                        ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            state.title.isEmpty ? '未知曲目' : state.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          Text(
                            [state.artist, state.album]
                                .where((value) => value.isNotEmpty)
                                .join(' · '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 18),
                    Expanded(
                      flex: 6,
                      child: Column(
                        children: [
                          Expanded(
                            child: Card(
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: state.lyrics.isEmpty
                                    ? const Center(child: Text('播放器未提供歌词'))
                                    : SingleChildScrollView(
                                        child: Text(
                                          state.lyrics,
                                          textAlign: TextAlign.center,
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodyLarge
                                              ?.copyWith(height: 1.6),
                                        ),
                                      ),
                              ),
                            ),
                          ),
                          _LabeledSlider(
                            icon: Icons.timelapse,
                            value: position,
                            max: duration,
                            leading: _time(position),
                            trailing: _time(state.duration),
                            onChanged: (value) {
                              setState(() => _dragPosition = value);
                            },
                            onChangeEnd: (value) {
                              _send('seek', value);
                              setState(() => _dragPosition = null);
                            },
                          ),
                          Row(
                            children: [
                              IconButton(
                                onPressed: () => _send('toggleMute'),
                                icon: Icon(
                                  state.muted
                                      ? Icons.volume_off
                                      : Icons.volume_up,
                                ),
                              ),
                              Expanded(
                                child: Slider(
                                  value: volume,
                                  onChanged: (value) {
                                    setState(() => _dragVolume = value);
                                  },
                                  onChangeEnd: (value) {
                                    _send('setVolume', value);
                                    setState(() => _dragVolume = null);
                                  },
                                ),
                              ),
                              SizedBox(
                                width: 42,
                                child: Text('${(volume * 100).round()}%'),
                              ),
                            ],
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _MediaButton(
                                icon: Icons.skip_previous,
                                onTap: () => _send('previous'),
                              ),
                              const SizedBox(width: 18),
                              _MediaButton(
                                icon: state.playing
                                    ? Icons.pause_rounded
                                    : Icons.play_arrow_rounded,
                                primary: true,
                                onTap: () => _send('playPause'),
                              ),
                              const SizedBox(width: 18),
                              _MediaButton(
                                icon: Icons.skip_next,
                                onTap: () => _send('next'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Uint8List? _artwork(String encoded) {
    if (encoded.isEmpty) return _cachedArtwork;
    if (encoded == _cachedArtworkText) return _cachedArtwork;
    try {
      _cachedArtworkText = encoded;
      _cachedArtwork = base64Decode(encoded);
    } catch (_) {}
    return _cachedArtwork;
  }

  void _send(String command, [double? value]) {
    RemoteLaunchpadService.instance.sendMediaCommand(
      widget.computerId,
      command,
      value,
    );
  }

  String _time(double seconds) {
    if (!seconds.isFinite || seconds < 0) return '0:00';
    final value = seconds.round();
    return '${value ~/ 60}:${(value % 60).toString().padLeft(2, '0')}';
  }
}

class _Unavailable extends StatelessWidget {
  const _Unavailable({required this.state});
  final RemoteMediaState state;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.music_off_outlined, size: 64),
          const SizedBox(height: 14),
          Text(state.message.isEmpty ? '电脑当前没有可控制的播放器' : state.message),
        ],
      ),
    );
  }
}

class _ArtworkFallback extends StatelessWidget {
  const _ArtworkFallback({required this.context});
  final BuildContext context;

  @override
  Widget build(BuildContext _) {
    return ColoredBox(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: const Icon(Icons.album, size: 90),
    );
  }
}

class _LabeledSlider extends StatelessWidget {
  const _LabeledSlider({
    required this.icon,
    required this.value,
    required this.max,
    required this.leading,
    required this.trailing,
    required this.onChanged,
    required this.onChangeEnd,
  });

  final IconData icon;
  final double value;
  final double max;
  final String leading;
  final String trailing;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: 7),
        Text(leading),
        Expanded(
          child: Slider(
            value: value,
            max: max,
            onChanged: onChanged,
            onChangeEnd: onChangeEnd,
          ),
        ),
        Text(trailing),
      ],
    );
  }
}

class _MediaButton extends StatelessWidget {
  const _MediaButton({
    required this.icon,
    required this.onTap,
    this.primary = false,
  });

  final IconData icon;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    return IconButton.filledTonal(
      onPressed: onTap,
      icon: Icon(icon),
      iconSize: primary ? 32 : 25,
      padding: EdgeInsets.all(primary ? 12 : 9),
      style: primary
          ? IconButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Theme.of(context).colorScheme.onPrimary,
            )
          : null,
    );
  }
}
