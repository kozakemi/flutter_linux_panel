import 'dart:ui';
import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../services/display_service.dart';
import 'widgets/spinning_player.dart';
import 'audio_cover.dart';
import 'fs/music_fs.dart';
import 'widgets/waveform_painter.dart';
import 'widgets/spectrum_painter.dart';

class MusicAppPage extends StatefulWidget {
  const MusicAppPage({super.key});

  @override
  State<MusicAppPage> createState() => _MusicAppPageState();
}

class _MusicAppPageState extends State<MusicAppPage> {
  static const String musicDirPath = '/mnt/tfcard/music';
  // static const String musicDirPath = '/home/tspi/音乐';
  final SoLoud _soloud = SoLoud.instance;
  final List<AudioSource> _sources = [];
  SoundHandle? _currentHandle;
  final List<String> _tracks = [];
  bool _loading = true;
  String? _error;
  int? _currentIndex;
  Timer? _posTimer;
  Timer? _vizTimer;
  List<double> _vizSamples = const [];
  List<double> _vizFft = const [];
  static const double _smoothAlpha = 0.35;
  final GlobalKey _controlsKey = GlobalKey();
  double _controlsHeight = 0;

  @override
  void initState() {
    super.initState();
    _init();
    _posTimer = Timer.periodic(const Duration(milliseconds: 500), (t) {
      if (_currentHandle != null &&
          _soloud.getIsValidVoiceHandle(_currentHandle!)) {
        setState(() {});
      }
    });
    _vizTimer = Timer.periodic(const Duration(milliseconds: 60), (t) {
      if (_isPlaying()) {
        _updateVisualizationSamples();
      }
    });
  }

  Future<void> _init() async {
    try {
      if (!_soloud.isInitialized) {
        await _soloud.init();
        _soloud.setVisualizationEnabled(true);
      }
      final entries = await scanAudioFiles(musicDirPath, _isAudioFile);

      setState(() {
        _tracks
          ..clear()
          ..addAll(entries);
        _sources.clear();
        _loading = false;
        _error = _tracks.isEmpty ? '未在 $musicDirPath 找到音频文件' : null;
      });
    } catch (e) {
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

  Future<void> _playAt(int index) async {
    if (index < 0 || index >= _tracks.length) return;

    try {
      // 释放之前的句柄
      if (_currentHandle != null) {
        await _soloud.stop(_currentHandle!);
        _currentHandle = null;
      }

      // 懒加载并缓存 AudioSource
      if (_sources.length != _tracks.length) {
        _sources
          ..clear()
          ..addAll(await Future.wait(_tracks.map((p) => _soloud.loadFile(p))));
      }

      final src = _sources[index];
      final handle = await _soloud.play(src);
      setState(() {
        _currentIndex = index;
        _currentHandle = handle;
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('播放失败：$e')),
      );
    }
  }

  @override
  void dispose() {
    // 停止当前播放并释放资源
    if (_currentHandle != null) {
      _soloud.stop(_currentHandle!);
      _currentHandle = null;
    }
    _soloud.disposeAllSources();
    _soloud.deinit();
    _posTimer?.cancel();
    _vizTimer?.cancel();
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
      backgroundColor: const Color(0xFFF2F2F7),
      appBar: AppBar(
        title: const Text('音乐'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
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
    final playing = _currentHandle != null &&
        _soloud.getIsValidVoiceHandle(_currentHandle!) &&
        !_soloud.getPause(_currentHandle!);
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
                return Image.memory(
                  coverBytes,
                  fit: BoxFit.cover,
                );
              }
              return Image.asset(
                'source/background/b8d50820181ef8bbb8514e6813281294.jpg',
                fit: BoxFit.cover,
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
                    cover: SvgPicture.asset(
                      'source/app_ico/Music.svg',
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                const SizedBox(height: 16),
              ],
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: _controlsHeight,
              height: MediaQuery.of(context).size.height * 0.16,
              child: IgnorePointer(
                child: AnimatedOpacity(
                  opacity: 1.0,
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOut,
                  child: CustomPaint(
                    painter: SpectrumPainter(
                      fft: _vizFft.isNotEmpty
                          ? _vizFft
                          : List<double>.filled(256, 0.0),
                      color: Colors.white.withOpacity(0.6),
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

  List<double> _lastSamples = const [];
  List<double> _getWaveSamples() {
    try {
      if (_currentHandle != null &&
          _soloud.getIsValidVoiceHandle(_currentHandle!)) {
        final audioData = AudioData(GetSamplesKind.wave);
        audioData.updateSamples();
        final samples = audioData.getAudioData(
          alwaysReturnData: false,
        );
        audioData.dispose();
        if (samples != null && samples.isNotEmpty) {
          _lastSamples = samples;
        }
      }
    } catch (_) {}
    return _lastSamples.isNotEmpty
        ? _lastSamples
        : List<double>.filled(256, 0.0);
  }

  void _updateVisualizationSamples() {
    try {
      final audioData = AudioData(GetSamplesKind.linear);
      audioData.updateSamples();
      final linear = audioData.getAudioData(alwaysReturnData: false);
      audioData.dispose();
      if (linear != null && linear.isNotEmpty) {
        final half = (linear.length / 2).floor();
        final fft = linear.sublist(0, half);
        final wave = linear.sublist(half);
        if (_vizFft.isEmpty) {
          _vizFft = fft;
          _vizSamples = wave;
        } else {
          final lenF = fft.length;
          final outF = List<double>.filled(lenF, 0.0);
          for (int i = 0; i < lenF; i++) {
            outF[i] = _smoothAlpha * fft[i] + (1 - _smoothAlpha) * _vizFft[i];
          }
          _vizFft = outF;

          final lenW = wave.length;
          final outW = List<double>.filled(lenW, 0.0);
          for (int i = 0; i < lenW; i++) {
            outW[i] =
                _smoothAlpha * wave[i] + (1 - _smoothAlpha) * _vizSamples[i];
          }
          _vizSamples = outW;
        }
        if (mounted) setState(() {});
      }
    } catch (_) {}
  }

  bool _isPlaying() {
    return _currentHandle != null &&
        _soloud.getIsValidVoiceHandle(_currentHandle!) &&
        !_soloud.getPause(_currentHandle!);
  }

  bool _isPaused() {
    return _currentHandle != null &&
        _soloud.getIsValidVoiceHandle(_currentHandle!) &&
        _soloud.getPause(_currentHandle!);
  }

  Widget? _buildControls(BuildContext context) {
    if (kIsWeb) {
      return null;
    }
    final totalMs = (_currentIndex != null && _sources.length == _tracks.length)
        ? _soloud.getLength(_sources[_currentIndex!]).inMilliseconds
        : 0;
    final posMs = (_currentHandle != null &&
            _soloud.getIsValidVoiceHandle(_currentHandle!))
        ? _soloud.getPosition(_currentHandle!).inMilliseconds
        : 0;
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
                  value: (totalMs > 0
                          ? clampedPos.toDouble()
                          : 0.0)
                      .clamp(0.0, totalMs > 0 ? totalMs.toDouble() : 1.0),
                  onChanged: totalMs > 0
                      ? (v) {
                          setState(() {});
                        }
                      : null,
                  onChangeEnd: totalMs > 0
                      ? (v) {
                          try {
                            if (_currentHandle != null) {
                              _soloud.seek(_currentHandle!,
                                  Duration(milliseconds: v.toInt()));
                              setState(() {});
                            }
                          } catch (e) {
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
                icon: Icon((_currentHandle != null &&
                        !_soloud.getPause(_currentHandle!))
                    ? Icons.pause_circle_filled
                    : Icons.play_circle_fill),
                iconSize: 36,
                color: Colors.blue,
                tooltip: (_currentHandle != null &&
                        !_soloud.getPause(_currentHandle!))
                    ? '暂停'
                    : '播放',
                onPressed: () async {
                  try {
                    if (_currentHandle == null) {
                      // 如果没有当前播放，播放当前索引或第一首
                      final idx = _currentIndex ?? 0;
                      await _playAt(idx);
                    } else {
                      // 切换暂停/继续
                      final paused = _soloud.getPause(_currentHandle!);
                      _soloud.setPause(_currentHandle!, !paused);
                    }
                    setState(() {});
                  } catch (e) {
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
                    if (_currentHandle != null) {
                      await _soloud.stop(_currentHandle!);
                      _currentHandle = null;
                    }
                    setState(() {});
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
                      final playing = _currentIndex == i &&
                          _currentHandle != null &&
                          _soloud.getIsValidVoiceHandle(_currentHandle!) &&
                          !_soloud.getPause(_currentHandle!);
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
                              child: Icon(Icons.music_note),
                              radius: 18,
                            );
                          },
                        ),
                        title: Text(name),
                        trailing: playing ? const Icon(Icons.equalizer) : null,
                        onTap: () async {
                          await _playAt(i);
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
