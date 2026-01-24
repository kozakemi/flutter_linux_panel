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
import 'dart:developer' as developer;
import 'dart:io';

import '../models/brightness_models.dart';

/// 原生亮度服务（Linux）
///
/// 优先使用 brightnessctl，如果不可用则退回到 /sys/class/backlight
class NativeBrightnessService {
  static final NativeBrightnessService instance = NativeBrightnessService._();
  NativeBrightnessService._();

  final StreamController<BrightnessStatus> _statusController =
      StreamController<BrightnessStatus>.broadcast();

  BrightnessStatus _currentStatus = const BrightnessStatus(
    current: 50,
    max: 100,
    autoEnabled: false,
    available: false,
  );

  bool _initialized = false;
  bool _useBrightnessctl = false;
  String? _backlightPath; // /sys/class/backlight/<device>

  Timer? _pollTimer;

  /// 亮度状态流
  Stream<BrightnessStatus> get statusStream => _statusController.stream;

  /// 当前状态
  BrightnessStatus get currentStatus => _currentStatus;

  bool get isInitialized => _initialized;

  /// 初始化服务，检测可用的亮度控制后端
  Future<void> initialize() async {
    if (_initialized) return;

    developer.log('初始化原生亮度服务', name: 'NativeBrightnessService');

    try {
      // 只在 Linux 下尝试原生亮度控制
      if (!Platform.isLinux) {
        developer.log('当前平台非 Linux，亮度控制不可用', name: 'NativeBrightnessService');
        _setStatus(_currentStatus.copyWith(available: false));
        _initialized = true;
        return;
      }

      // 1. 尝试检测 brightnessctl
      try {
        final result = await Process.run('brightnessctl', ['-h']);
        if (result.exitCode == 0) {
          _useBrightnessctl = true;
          developer.log('检测到 brightnessctl，可用于亮度控制', name: 'NativeBrightnessService');
        }
      } catch (_) {
        _useBrightnessctl = false;
      }

      // 2. 如果没有 brightnessctl，尝试 /sys/class/backlight
      if (!_useBrightnessctl) {
        final sysDir = Directory('/sys/class/backlight');
        if (await sysDir.exists()) {
          final devices = await sysDir
              .list()
              .where((e) => e is Directory)
              .cast<Directory>()
              .toList();
          if (devices.isNotEmpty) {
            _backlightPath = devices.first.path;
            developer.log('使用 backlight 目录: $_backlightPath', name: 'NativeBrightnessService');
          }
        }
      }

      final available = _useBrightnessctl || _backlightPath != null;
      _initialized = true;

      // 获取一次初始状态
      if (available) {
        await getStatus();
      } else {
        _setStatus(_currentStatus.copyWith(available: false));
      }

      // 周期性轮询，保持 UI 同步
      _pollTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
        if (!_initialized) {
          timer.cancel();
          return;
        }
        getStatus().catchError((e) {
          developer.log('轮询亮度状态失败: $e', name: 'NativeBrightnessService');
        });
      });
    } catch (e, stackTrace) {
      developer.log(
        '原生亮度服务初始化失败: $e',
        name: 'NativeBrightnessService',
        error: e,
        stackTrace: stackTrace,
      );
      _initialized = true;
      _setStatus(_currentStatus.copyWith(available: false));
    }
  }

  /// 释放资源
  Future<void> dispose() async {
    _pollTimer?.cancel();
    _pollTimer = null;
    _initialized = false;
    await _statusController.close();
  }

  /// 获取当前亮度状态
  Future<BrightnessStatus?> getStatus() async {
    if (!_initialized) {
      await initialize();
    }

    if (!_useBrightnessctl && _backlightPath == null) {
      _setStatus(_currentStatus.copyWith(available: false));
      return _currentStatus;
    }

    try {
      int current = 0;
      int max = 100;

      if (_useBrightnessctl) {
        final curResult = await Process.run('brightnessctl', ['g']);
        final maxResult = await Process.run('brightnessctl', ['m']);
        if (curResult.exitCode == 0 && maxResult.exitCode == 0) {
          final curRaw = int.tryParse(curResult.stdout.toString().trim()) ?? 0;
          final maxRaw = int.tryParse(maxResult.stdout.toString().trim()) ?? 1;
          max = maxRaw;
          current = curRaw.clamp(0, maxRaw);
        }
      } else if (_backlightPath != null) {
        final curFile = File('$_backlightPath/brightness');
        final maxFile = File('$_backlightPath/max_brightness');
        if (await curFile.exists() && await maxFile.exists()) {
          final curRaw = int.tryParse((await curFile.readAsString()).trim()) ?? 0;
          final maxRaw = int.tryParse((await maxFile.readAsString()).trim()) ?? 1;
          max = maxRaw;
          current = curRaw.clamp(0, maxRaw);
        }
      }

      // 转换为百分比（0-100）
      final percent = max > 0 ? ((current / max) * 100).round().clamp(0, 100) : 0;

      final status = BrightnessStatus(
        current: percent,
        max: 100,
        autoEnabled: false,
        available: true,
      );

      _setStatus(status);
      return status;
    } catch (e, stackTrace) {
      developer.log(
        '获取亮度状态失败: $e',
        name: 'NativeBrightnessService',
        error: e,
        stackTrace: stackTrace,
      );
      _setStatus(_currentStatus.copyWith(available: false));
      return null;
    }
  }

  /// 设置亮度百分比 (0-100)
  Future<bool> setBrightness(int percent) async {
    if (!_initialized) {
      await initialize();
    }

    percent = percent.clamp(0, 100);

    if (!_useBrightnessctl && _backlightPath == null) {
      developer.log('没有可用的亮度后端', name: 'NativeBrightnessService');
      return false;
    }

    try {
      if (_useBrightnessctl) {
        // brightnessctl 支持直接设置百分比
        final result =
            await Process.run('brightnessctl', ['set', '$percent%']);
        if (result.exitCode != 0) {
          developer.log(
            'brightnessctl 设置亮度失败: ${result.stderr}',
            name: 'NativeBrightnessService',
          );
          return false;
        }
      } else if (_backlightPath != null) {
        final maxFile = File('$_backlightPath/max_brightness');
        final curFile = File('$_backlightPath/brightness');
        if (await maxFile.exists() && await curFile.exists()) {
          final maxRaw =
              int.tryParse((await maxFile.readAsString()).trim()) ?? 1;
          final newRaw =
              ((percent / 100.0) * maxRaw).round().clamp(0, maxRaw);
          await curFile.writeAsString('$newRaw');
        } else {
          return false;
        }
      }

      // 更新状态
      await getStatus();
      return true;
    } catch (e, stackTrace) {
      developer.log(
        '设置亮度失败: $e',
        name: 'NativeBrightnessService',
        error: e,
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  void _setStatus(BrightnessStatus status) {
    _currentStatus = status;
    if (!_statusController.isClosed) {
      _statusController.add(status);
    }
  }
}

