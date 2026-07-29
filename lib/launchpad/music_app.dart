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
import 'dart:ui';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../services/display_service.dart';
import 'audio_cover.dart';
import 'fs/music_fs.dart';
import 'widgets/spectrum_painter.dart';
import 'widgets/spinning_player.dart';

class MusicAppPage extends StatefulWidget {
  const MusicAppPage({super.key, this.initialTrackPath});

  final String? initialTrackPath;

  @override
  State<MusicAppPage> createState() => _MusicAppPageState();
}

class _MusicAppPageState extends State<MusicAppPage> {
  static const String musicDirPath = '/mnt/tfcard/music';
  // static const String musicDirPath = '/home/tspi/音乐';
  late final AudioPlayer _player;
  final List<String> _tracks = [];
  bool _loading = true;
  String? _error;
  int? _currentIndex;
  PlayerState _playerState = PlayerState.stopped;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  double _volume = 1;
  double? _dragPositionMs;
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<Duration>? _durationSubscription;
  StreamSubscription<PlayerState>? _playerStateSubscription;
  StreamSubscription<void>? _playerCompleteSubscription;
  int _playRequestId = 0;
  final GlobalKey _controlsKey = GlobalKey();
  double _controlsHeight = 0;

  @override
  void initState() {
    super.initState();
    _player = AudioPlayer();
    _positionSubscription = _player.onPositionChanged.listen((position) {
      if (!mounted || _dragPositionMs != null) return;
      setState(() => _position = position);
    });
    _durationSubscription = _player.onDurationChanged.listen((duration) {
      if (!mounted) return;
      setState(() => _duration = duration);
    });
    _playerStateSubscription = _player.onPlayerStateChanged.listen((state) {
      if (!mounted) return;
      setState(() => _playerState = state);
    });
    _playerCompleteSubscription = _player.onPlayerComplete.listen((_) {
      if (!mounted) return;
      setState(() {
        _playerState = PlayerState.completed;
        _position = Duration.zero;
      });
    });
    _init();
  }

  Future<void> _init() async {
    final initialTrackPath = widget.initialTrackPath;
    final scanPath = initialTrackPath == null
        ? musicDirPath
        : _parentDirectory(initialTrackPath);
    try {
      List<String> entries;
      try {
        // initialTrackPath 模式只扫描所在目录的直接子文件，并跳过隐藏项
        entries = await scanAudioFiles(
          scanPath,
          _isAudioFile,
          recursive: initialTrackPath == null,
          includeHidden: initialTrackPath == null,
        );
      } catch (_) {
        // 扫描失败时至少保证被打开的文件可以播放
        if (initialTrackPath == null) rethrow;
        entries = <String>[];
      }
      if (initialTrackPath != null && !entries.contains(initialTrackPath)) {
        entries.insert(0, initialTrackPath);
      }
      final initialIndex =
          initialTrackPath == null ? -1 : entries.indexOf(initialTrackPath);

      if (!mounted) return;
      setState(() {
        _tracks
          ..clear()
          ..addAll(entries);
        _currentIndex = initialIndex >= 0 ? initialIndex : null;
        _loading = false;
        _error = _tracks.isEmpty ? '未在 $scanPath 找到音频文件' : null;
      });
      if (initialIndex >= 0) {
        await _playAt(initialIndex);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '扫描目录失败：$e';
      });
    }
  }

  bool _isAudioFile(String path) {
    final lower = path.toLowerCase();
    return lower.endsWith('.mp3') ||
        lower.endsWith('.flac') ||
        lower.endsWith('.wav') ||
        lower.endsWith('.m4a') ||
        lower.endsWith('.aac') ||
        lower.endsWith('.ogg');
  }

  String _parentDirectory(String path) {
    final normalized = path.replaceAll('\\', '/');
    final separator = normalized.lastIndexOf('/');
    if (separator <= 0) {
      return separator == 0 ? '/' : '.';
    }
    return normalized.substring(0, separator);
  }

  Future<void> _playAt(int index) async {
    if (index < 0 || index >= _tracks.length) return;

    final requestId = ++_playRequestId;
    try {
      await _player.stop();
      if (!mounted || requestId != _playRequestId) return;
      setState(() {
        _currentIndex = index;
        _position = Duration.zero;
        _duration = Duration.zero;
        _dragPositionMs = null;
      });
      await _player.play(
        DeviceFileSource(_tracks[index]),
        volume: _volume,
      );
      await _resumeWhenPrepared(requestId);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('播放失败：$e')),
      );
    }
  }

  Future<void> _resumeWhenPrepared(int requestId) async {
    // The eLinux backend can pause the GStreamer pipeline when it reaches
    // READY, racing with the first resume sent by AudioPlayer.play().
    // Once metadata is queryable, resume once more to enter PLAYING reliably.
    for (var attempt = 0; attempt < 20; attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      if (!mounted ||
          requestId != _playRequestId ||
          _playerState != PlayerState.playing) {
        return;
      }

      Duration? duration;
      try {
        duration = await _player.getDuration();
      } catch (_) {
        continue;
      }
      if (duration != null && duration > Duration.zero) {
        final Duration preparedDuration = duration;
        await _player.resume();
        if (!mounted || requestId != _playRequestId) return;
        setState(() => _duration = preparedDuration);
        return;
      }
    }

    // Some formats do not expose duration until playback has progressed.
    if (mounted &&
        requestId == _playRequestId &&
        _playerState == PlayerState.playing) {
      await _player.resume();
    }
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    _durationSubscription?.cancel();
    _playerStateSubscription?.cancel();
    _playerCompleteSubscription?.cancel();
    unawaited(_player.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final h = _controlsKey.currentContext?.size?.height ?? 0;
      if (h != _controlsHeight) {
        if (mounted) {
          setState(() {
            _controlsHeight = h;
          });
        }
      }
    });
    final scale = DisplayService.instance.scaleFactor;
    final iconSize = 24.0 * scale;
    final toolbarHeight = 56.0 * scale;
    final leadingWidth = 56.0 * scale;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('音乐'),
        toolbarHeight: toolbarHeight,
        leadingWidth: leadingWidth,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          iconSize: iconSize,
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            iconSize: iconSize,
            tooltip: '重新扫描',
            onPressed: _loading
                ? null
                : () async {
                    setState(() {
                      _loading = true;
                      _error = null;
                      _tracks.clear();
                    });
                    await _init();
                  },
          ),
        ],
      ),
      body: _buildBody(context),
      bottomNavigationBar: _buildControls(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(child: Text(_error!));
    }
    final playing = _playerState == PlayerState.playing;
    final bgTrack = (_currentIndex != null && _tracks.isNotEmpty)
        ? _tracks[_currentIndex!]
        : (_tracks.isNotEmpty ? _tracks.first : null);
    return Stack(
      children: [
        Positioned.fill(
          child: FutureBuilder(
            future: bgTrack == null
                ? Future.value(null)
                : readEmbeddedCover(bgTrack),
            builder: (context, snapshot) {
              final coverBytes = snapshot.data;
              if (coverBytes != null) {
                return ImageFiltered(
                  imageFilter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                  child: Image.memory(
                    coverBytes,
                    fit: BoxFit.cover,
                  ),
                );
              }
              return ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                child: Image.asset(
                  'source/background/b8d50820181ef8bbb8514e6813281294.jpg',
                  fit: BoxFit.cover,
                ),
              );
            },
          ),
        ),
        Positioned.fill(
          child: Container(color: const Color(0x33000000)),
        ),
        Stack(
          children: [
            ListView(
              children: [
                const SizedBox(height: 24),
                Center(
                  child: SpinningPlayer(
                    playing: playing,
                    trackPath: (_currentIndex != null && _tracks.isNotEmpty)
                        ? _tracks[_currentIndex!]
                        : (_tracks.isNotEmpty ? _tracks.first : null),
                    size: MediaQuery.of(context).size.shortestSide * 0.6,
                  ),
                ),
                const SizedBox(height: 12),
                const SizedBox(height: 16),
              ],
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: MediaQuery.of(context).size.height * 0.16,
              child: IgnorePointer(
                child: AnimatedOpacity(
                  opacity: 1.0,
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOut,
                  child: CustomPaint(
                    painter: SpectrumPainter(
                      fft: List<double>.filled(256, 0.0),
                      color: Colors.white.withValues(alpha: 0.9),
                      bins: 16,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  String _two(int n) => n.toString().padLeft(2, '0');
  String _formatTime(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '${_two(m)}:${_two(s)}';
  }

  bool _isPlaying() {
    return _playerState == PlayerState.playing;
  }

  Widget? _buildControls(BuildContext context) {
    if (kIsWeb) {
      return null;
    }
    // Some backends report a negative duration while the media metadata is
    // still being loaded. Treat that sentinel value as an unknown duration.
    final totalMs = _duration.inMilliseconds > 0 ? _duration.inMilliseconds : 0;
    final posMs = (_dragPositionMs ?? _position.inMilliseconds).round();
    final clampedPos = posMs.clamp(0, totalMs);
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      key: _controlsKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Column(
              children: [
                Slider(
                  min: 0,
                  max: totalMs > 0 ? totalMs.toDouble() : 1.0,
                  value: (totalMs > 0 ? clampedPos.toDouble() : 0.0)
                      .clamp(0.0, totalMs > 0 ? totalMs.toDouble() : 1.0),
                  onChanged: totalMs > 0
                      ? (v) {
                          setState(() => _dragPositionMs = v);
                        }
                      : null,
                  onChangeEnd: totalMs > 0
                      ? (v) async {
                          try {
                            await _player.seek(
                              Duration(milliseconds: v.round()),
                            );
                            if (!mounted) return;
                            setState(() {
                              _position = Duration(milliseconds: v.round());
                              _dragPositionMs = null;
                            });
                          } catch (e) {
                            if (!context.mounted) return;
                            setState(() => _dragPositionMs = null);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('拖动失败：$e')),
                            );
                          }
                        }
                      : null,
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(_formatTime(Duration(milliseconds: clampedPos))),
                    Text(
                        '-${_formatTime(Duration(milliseconds: (totalMs - clampedPos).clamp(0, totalMs)))}'),
                  ],
                ),
              ],
            ),
          ),
          Row(
            children: [
              const Icon(Icons.volume_down),
              Expanded(
                child: Slider(
                  min: 0,
                  max: 1,
                  value: _volume,
                  onChanged: (value) {
                    setState(() => _volume = value);
                    unawaited(_player.setVolume(value));
                  },
                ),
              ),
              const Icon(Icons.volume_up),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton(
                icon: const Icon(Icons.skip_previous),
                tooltip: '上一曲',
                onPressed: () async {
                  try {
                    if (_tracks.isEmpty) return;
                    final next = (_currentIndex == null)
                        ? 0
                        : (_currentIndex! - 1 + _tracks.length) %
                            _tracks.length;
                    await _playAt(next);
                  } catch (_) {}
                },
              ),
              IconButton(
                icon: Icon(_isPlaying()
                    ? Icons.pause_circle_filled
                    : Icons.play_circle_fill),
                iconSize: 36,
                color: Colors.blue,
                tooltip: _isPlaying() ? '暂停' : '播放',
                onPressed: () async {
                  try {
                    if (_currentIndex == null ||
                        _playerState == PlayerState.stopped ||
                        _playerState == PlayerState.completed) {
                      final idx = _currentIndex ?? 0;
                      await _playAt(idx);
                    } else if (_isPlaying()) {
                      await _player.pause();
                    } else {
                      await _player.resume();
                    }
                  } catch (e) {
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('操作失败：$e')),
                    );
                  }
                },
              ),
              IconButton(
                icon: const Icon(Icons.stop_circle),
                tooltip: '停止',
                onPressed: () async {
                  try {
                    ++_playRequestId;
                    await _player.stop();
                    if (!mounted) return;
                    setState(() => _position = Duration.zero);
                  } catch (_) {}
                },
              ),
              IconButton(
                icon: const Icon(Icons.skip_next),
                tooltip: '下一曲',
                onPressed: () async {
                  try {
                    if (_tracks.isEmpty) return;
                    final next = (_currentIndex == null)
                        ? 0
                        : (_currentIndex! + 1) % _tracks.length;
                    await _playAt(next);
                  } catch (_) {}
                },
              ),
              IconButton(
                icon: const Icon(Icons.queue_music),
                tooltip: '播放列表',
                onPressed: () {
                  _showPlaylistBottomSheet();
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showPlaylistBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return SafeArea(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  height: 4,
                  width: 36,
                  decoration: BoxDecoration(
                    color: Colors.black26,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 8),
                const Text('播放列表'),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: _tracks.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final path = _tracks[i];
                      final name = path.split('/').last;
                      final playing = _currentIndex == i && _isPlaying();
                      return ListTile(
                        leading: FutureBuilder(
                          future: readEmbeddedCover(path),
                          builder: (context, snapshot) {
                            final bytes = snapshot.data;
                            if (bytes != null) {
                              return CircleAvatar(
                                backgroundImage: MemoryImage(bytes),
                                radius: 18,
                              );
                            }
                            return const CircleAvatar(
                              radius: 18,
                              child: Icon(Icons.music_note),
                            );
                          },
                        ),
                        title: Text(name),
                        trailing: playing ? const Icon(Icons.equalizer) : null,
                        onTap: () async {
                          await _playAt(i);
                          if (!ctx.mounted) return;
                          Navigator.of(ctx).pop();
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
