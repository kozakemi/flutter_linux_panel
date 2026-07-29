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
import 'package:video_player/video_player.dart';

import '../../services/display_service.dart';

class VideoPlayerPage extends StatefulWidget {
  const VideoPlayerPage({super.key, required this.path});

  final String path;

  @override
  State<VideoPlayerPage> createState() => _VideoPlayerPageState();
}

class _VideoPlayerPageState extends State<VideoPlayerPage> {
  /// 控制栏自动隐藏的等待时长
  static const Duration _autoHideDelay = Duration(seconds: 4);

  VideoPlayerController? _controller;
  String? _error;
  bool _initialized = false;
  bool _controlsVisible = true;
  Timer? _hideTimer;

  /// 拖动进度条时的临时位置（毫秒），null 表示未在拖动
  double? _dragValue;

  /// 是否正在拖动音量条
  bool _volumeDragging = false;

  /// 当前音量（0~1），用于静音切换后恢复
  double _volume = 1.0;

  /// 静音前的音量，恢复时使用
  double _lastNonZeroVolume = 1.0;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      final controller = VideoPlayerController.file(File(widget.path));
      _controller = controller;
      controller.addListener(_onControllerUpdate);
      await controller.initialize();
      if (!mounted) return;
      setState(() {
        _initialized = true;
        _volume = controller.value.volume;
      });
      await controller.play();
      _scheduleAutoHide();
    } catch (error) {
      // 普通 Flutter Linux 缺少 video_player 平台实现，或文件无法解码时，
      // 在页面内提示而不是让应用崩溃。
      if (!mounted) return;
      setState(() {
        _error = '无法播放该视频：$error\n'
            '请确认当前平台支持视频播放（eLinux 需安装 GStreamer 及对应解码插件）。';
      });
    }
  }

  void _onControllerUpdate() {
    final controller = _controller;
    if (controller == null || !mounted) return;
    final value = controller.value;
    if (value.hasError && _error == null) {
      setState(() {
        _error = '视频解码失败：${value.errorDescription ?? '未知错误'}';
      });
      return;
    }
    // 刷新播放进度与播放状态
    setState(() {});
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _controller?.removeListener(_onControllerUpdate);
    _controller?.dispose();
    super.dispose();
  }

  bool get _isInteracting => _dragValue != null || _volumeDragging;

  /// 重置自动隐藏计时器：显示状态下若一段时间无交互则淡出控制栏
  void _scheduleAutoHide() {
    _hideTimer?.cancel();
    if (!_initialized || _error != null) return;
    _hideTimer = Timer(_autoHideDelay, () {
      if (!mounted || _isInteracting) return;
      setState(() {
        _controlsVisible = false;
      });
    });
  }

  /// 用户发生交互时调用：保持控制栏显示并重新计时
  void _onUserInteraction() {
    if (!_controlsVisible) {
      setState(() {
        _controlsVisible = true;
      });
    }
    _scheduleAutoHide();
  }

  void _togglePlay() {
    final controller = _controller;
    if (controller == null || !_initialized) return;
    if (controller.value.isPlaying) {
      controller.pause();
    } else {
      controller.play();
    }
    _onUserInteraction();
  }

  void _toggleControls() {
    setState(() {
      _controlsVisible = !_controlsVisible;
    });
    if (_controlsVisible) {
      _scheduleAutoHide();
    } else {
      _hideTimer?.cancel();
    }
  }

  void _setVolume(double volume) {
    final controller = _controller;
    if (controller == null || !_initialized) return;
    controller.setVolume(volume);
    setState(() {
      _volume = volume;
      if (volume > 0) {
        _lastNonZeroVolume = volume;
      }
    });
  }

  void _toggleMute() {
    if (_volume > 0) {
      _setVolume(0);
    } else {
      _setVolume(_lastNonZeroVolume > 0 ? _lastNonZeroVolume : 1.0);
    }
    _onUserInteraction();
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    final minutesText = minutes.toString().padLeft(2, '0');
    final secondsText = seconds.toString().padLeft(2, '0');
    if (hours > 0) {
      return '$hours:$minutesText:$secondsText';
    }
    return '$minutesText:$secondsText';
  }

  String _fileName(String path) {
    return path.split(RegExp(r'[/\\]')).last;
  }

  @override
  Widget build(BuildContext context) {
    final scale = DisplayService.instance.scaleFactor;
    // 出错或未初始化完成时始终显示顶栏，便于返回
    final topBarVisible = _controlsVisible || _error != null || !_initialized;
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _toggleControls,
        child: Stack(
          fit: StackFit.expand,
          children: [
            _buildContent(scale),
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: _buildOverlay(
                visible: topBarVisible,
                child: _buildTopBar(scale),
              ),
            ),
            if (_error == null && _initialized && _controller != null)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _buildOverlay(
                  visible: _controlsVisible,
                  child: _buildControlBar(_controller!, scale),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// 带淡入淡出的悬浮层，隐藏时不响应点击
  Widget _buildOverlay({required bool visible, required Widget child}) {
    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedOpacity(
        opacity: visible ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 250),
        child: child,
      ),
    );
  }

  Widget _buildTopBar(double scale) {
    final iconSize = 24.0 * scale;
    final toolbarHeight = 56.0 * scale;
    return Container(
      color: Colors.black54,
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: toolbarHeight,
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                iconSize: iconSize,
                tooltip: '返回',
                onPressed: () => Navigator.of(context).pop(),
              ),
              Expanded(
                child: Text(
                  _fileName(widget.path),
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Colors.white, fontSize: 18 * scale),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContent(double scale) {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline,
                color: Colors.white70,
                size: 48 * scale,
              ),
              SizedBox(height: 16 * scale),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white),
              ),
            ],
          ),
        ),
      );
    }
    final controller = _controller;
    if (controller == null || !_initialized) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }
    return Center(
      child: AspectRatio(
        aspectRatio: controller.value.aspectRatio <= 0
            ? 16 / 9
            : controller.value.aspectRatio,
        child: VideoPlayer(controller),
      ),
    );
  }

  IconData _volumeIcon() {
    if (_volume <= 0) return Icons.volume_off;
    if (_volume < 0.5) return Icons.volume_down;
    return Icons.volume_up;
  }

  Widget _buildControlBar(VideoPlayerController controller, double scale) {
    final value = controller.value;
    final durationMs = value.duration.inMilliseconds;
    final positionMs = _dragValue ??
        value.position.inMilliseconds.clamp(0, durationMs).toDouble();
    final displayedPosition = Duration(milliseconds: positionMs.round());
    return Container(
      color: Colors.black54,
      padding: EdgeInsets.symmetric(
        horizontal: 8 * scale,
        vertical: 4 * scale,
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            IconButton(
              icon: Icon(
                value.isPlaying ? Icons.pause : Icons.play_arrow,
                color: Colors.white,
              ),
              iconSize: 32 * scale,
              tooltip: value.isPlaying ? '暂停' : '播放',
              onPressed: _togglePlay,
            ),
            Text(
              _formatDuration(displayedPosition),
              style: TextStyle(color: Colors.white, fontSize: 13 * scale),
            ),
            Expanded(
              child: Slider(
                value: durationMs > 0
                    ? positionMs.clamp(0, durationMs.toDouble()).toDouble()
                    : 0,
                max: durationMs > 0 ? durationMs.toDouble() : 1,
                activeColor: Colors.white,
                inactiveColor: Colors.white30,
                onChangeStart: durationMs > 0
                    ? (newValue) {
                        _hideTimer?.cancel();
                        setState(() {
                          _dragValue = newValue;
                        });
                      }
                    : null,
                onChanged: durationMs > 0
                    ? (newValue) {
                        setState(() {
                          _dragValue = newValue;
                        });
                      }
                    : null,
                onChangeEnd: durationMs > 0
                    ? (newValue) {
                        controller
                            .seekTo(Duration(milliseconds: newValue.round()));
                        setState(() {
                          _dragValue = null;
                        });
                        _scheduleAutoHide();
                      }
                    : null,
              ),
            ),
            Text(
              _formatDuration(value.duration),
              style: TextStyle(color: Colors.white, fontSize: 13 * scale),
            ),
            SizedBox(width: 8 * scale),
            IconButton(
              icon: Icon(_volumeIcon(), color: Colors.white),
              iconSize: 24 * scale,
              tooltip: _volume > 0 ? '静音' : '恢复音量',
              onPressed: _toggleMute,
            ),
            SizedBox(
              width: 96 * scale,
              child: Slider(
                value: _volume.clamp(0.0, 1.0),
                max: 1.0,
                activeColor: Colors.white,
                inactiveColor: Colors.white30,
                onChangeStart: (newValue) {
                  _hideTimer?.cancel();
                  setState(() {
                    _volumeDragging = true;
                  });
                  _setVolume(newValue);
                },
                onChanged: _setVolume,
                onChangeEnd: (newValue) {
                  setState(() {
                    _volumeDragging = false;
                  });
                  _setVolume(newValue);
                  _scheduleAutoHide();
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
