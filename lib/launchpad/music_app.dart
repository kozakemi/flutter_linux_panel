import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'fs/music_fs.dart';

class MusicAppPage extends StatefulWidget {
  const MusicAppPage({super.key});

  @override
  State<MusicAppPage> createState() => _MusicAppPageState();
}

class _MusicAppPageState extends State<MusicAppPage> {
  static const String musicDirPath = '/mnt/tfcard/music';
  final SoLoud _soloud = SoLoud.instance;
  final List<AudioSource> _sources = [];
  SoundHandle? _currentHandle;
  final List<String> _tracks = [];
  bool _loading = true;
  String? _error;
  int? _currentIndex;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      if (!_soloud.isInitialized) {
        await _soloud.init();
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F7),
      appBar: AppBar(
        title: const Text('音乐'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '重新扫描',
            onPressed: _loading ? null : () async {
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
    return ListView(
      children: [
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Material(
            color: Colors.white,
            surfaceTintColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                ListTile(
                  title: const Text('音乐目录'),
                  subtitle: Text(musicDirPath),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Text(
                      _error!,
                      style: const TextStyle(color: Colors.redAccent),
                    ),
                  ),
                if (_tracks.isNotEmpty)
                  ...ListTile.divideTiles(
                    context: context,
                    tiles: List.generate(_tracks.length, (i) {
                      final path = _tracks[i];
                      final name = path.split('/').last;
                      final playing = _currentIndex == i &&
                          _currentHandle != null &&
                          _soloud.getIsValidVoiceHandle(_currentHandle!) &&
                          !_soloud.getPause(_currentHandle!);
                      return ListTile(
                        leading: Icon(
                          playing ? Icons.equalizer : Icons.music_note,
                          color: playing ? Colors.green : Colors.blue,
                        ),
                        title: Text(name),
                        subtitle: Text(path),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: kIsWeb ? null : () => _playAt(i),
                      );
                    }),
                  ).toList(),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget? _buildControls(BuildContext context) {
    if (kIsWeb) {
      return null;
    }
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          IconButton(
            icon: const Icon(Icons.skip_previous),
            tooltip: '上一曲',
            onPressed: () async {
              try {
                if (_tracks.isEmpty) return;
                final next = (_currentIndex == null) ? 0 : (_currentIndex! - 1 + _tracks.length) % _tracks.length;
                await _playAt(next);
              } catch (_) {}
            },
          ),
          IconButton(
            icon: Icon((_currentHandle != null && !_soloud.getPause(_currentHandle!))
                ? Icons.pause_circle_filled
                : Icons.play_circle_fill),
            iconSize: 36,
            color: Colors.blue,
            tooltip: (_currentHandle != null && !_soloud.getPause(_currentHandle!)) ? '暂停' : '播放',
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
                final next = (_currentIndex == null) ? 0 : (_currentIndex! + 1) % _tracks.length;
                await _playAt(next);
              } catch (_) {}
            },
          ),
        ],
      ),
    );
  }
}