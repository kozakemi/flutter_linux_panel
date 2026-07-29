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
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import '../models/brightness_models.dart';

/// Linux 屏幕亮度服务。
///
/// 直接读写 sysfs backlight 接口，优先使用 brightnessctl，退回到
/// `/sys/class/backlight/<device>`。写入通常要求用户属于 `video` 组。
/// 该实现为纯 Dart，不依赖外部包，可在 flutter 与 flutter-elinux 两套
/// 工具链下编译。
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
  String? _backlightPath;
  Timer? _pollTimer;

  Stream<BrightnessStatus> get statusStream => _statusController.stream;
  BrightnessStatus get currentStatus => _currentStatus;
  bool get isInitialized => _initialized;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    try {
      // #region debug-point D:brightness-service-initialize
      (() async {
        try {
          var debugServerUrl = 'http://198.18.0.1:7778/event';
          var debugSessionId = 'display-settings-crash';
          try {
            final env =
                await File('.dbg/display-settings-crash.env').readAsString();
            for (final line in env.split('\n')) {
              if (line.startsWith('DEBUG_SERVER_URL=')) {
                debugServerUrl = line.substring('DEBUG_SERVER_URL='.length);
              } else if (line.startsWith('DEBUG_SESSION_ID=')) {
                debugSessionId = line.substring('DEBUG_SESSION_ID='.length);
              }
            }
          } catch (_) {}
          final client = HttpClient();
          final req = await client.postUrl(Uri.parse(debugServerUrl));
          req.headers.contentType = ContentType.json;
          req.write(
            jsonEncode({
              'sessionId': debugSessionId,
              'runId': 'pre-fix',
              'hypothesisId': 'D',
              'location': 'lib/services/native_brightness_service.dart:57',
              'msg': '[DEBUG] brightness service initialize entered',
              'data': {'initialized': _initialized},
              'ts': DateTime.now().millisecondsSinceEpoch,
            }),
          );
          await req.close();
          client.close();
        } catch (_) {}
      })();
      // #endregion
      if (!Platform.isLinux) {
        _setStatus(_currentStatus.copyWith(available: false));
        return;
      }

      // flutter-elinux embedders may not support spawning subprocesses
      // reliably. Reading sysfs directly also avoids depending on
      // brightnessctl being installed on the target image.
      final sysDir = Directory('/sys/class/backlight');
      if (await sysDir.exists()) {
        final devices = await sysDir
            .list()
            .where((e) => e is Directory)
            .cast<Directory>()
            .toList();
        if (devices.isNotEmpty) {
          _backlightPath = devices.first.path;
        }
      }

      final available = _backlightPath != null;
      // #region debug-point D:brightness-service-backend
      (() async {
        try {
          var debugServerUrl = 'http://198.18.0.1:7778/event';
          var debugSessionId = 'display-settings-crash';
          try {
            final env =
                await File('.dbg/display-settings-crash.env').readAsString();
            for (final line in env.split('\n')) {
              if (line.startsWith('DEBUG_SERVER_URL=')) {
                debugServerUrl = line.substring('DEBUG_SERVER_URL='.length);
              } else if (line.startsWith('DEBUG_SESSION_ID=')) {
                debugSessionId = line.substring('DEBUG_SESSION_ID='.length);
              }
            }
          } catch (_) {}
          final client = HttpClient();
          final req = await client.postUrl(Uri.parse(debugServerUrl));
          req.headers.contentType = ContentType.json;
          req.write(
            jsonEncode({
              'sessionId': debugSessionId,
              'runId': 'pre-fix',
              'hypothesisId': 'D',
              'location': 'lib/services/native_brightness_service.dart:86',
              'msg': '[DEBUG] brightness backend resolved',
              'data': {
                'backlightPath': _backlightPath,
                'available': available,
              },
              'ts': DateTime.now().millisecondsSinceEpoch,
            }),
          );
          await req.close();
          client.close();
        } catch (_) {}
      })();
      // #endregion
      if (available) {
        await getStatus();
        _pollTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
          if (!_initialized) {
            timer.cancel();
            return;
          }
          getStatus().catchError((e) {
            developer.log('轮询亮度状态失败: $e', name: 'NativeBrightnessService');
            return null;
          });
        });
      } else {
        _setStatus(_currentStatus.copyWith(available: false));
      }
    } catch (error, stackTrace) {
      _handleError(error, stackTrace);
    }
  }

  Future<BrightnessStatus?> getStatus() async {
    if (!_initialized) {
      await initialize();
    }

    // #region debug-point D:brightness-service-get-status
    (() async {
      try {
        var debugServerUrl = 'http://198.18.0.1:7778/event';
        var debugSessionId = 'display-settings-crash';
        try {
          final env =
              await File('.dbg/display-settings-crash.env').readAsString();
          for (final line in env.split('\n')) {
            if (line.startsWith('DEBUG_SERVER_URL=')) {
              debugServerUrl = line.substring('DEBUG_SERVER_URL='.length);
            } else if (line.startsWith('DEBUG_SESSION_ID=')) {
              debugSessionId = line.substring('DEBUG_SESSION_ID='.length);
            }
          }
        } catch (_) {}
        final client = HttpClient();
        final req = await client.postUrl(Uri.parse(debugServerUrl));
        req.headers.contentType = ContentType.json;
        req.write(
          jsonEncode({
            'sessionId': debugSessionId,
            'runId': 'pre-fix',
            'hypothesisId': 'D',
            'location': 'lib/services/native_brightness_service.dart:117',
            'msg': '[DEBUG] brightness getStatus entered',
            'data': {
              'backlightPath': _backlightPath,
            },
            'ts': DateTime.now().millisecondsSinceEpoch,
          }),
        );
        await req.close();
        client.close();
      } catch (_) {}
    })();
    // #endregion

    if (_backlightPath == null) {
      _setStatus(_currentStatus.copyWith(available: false));
      return _currentStatus;
    }

    try {
      int current = 0;
      int max = 100;

      if (_backlightPath != null) {
        final curFile = File('$_backlightPath/brightness');
        final maxFile = File('$_backlightPath/max_brightness');
        if (await curFile.exists() && await maxFile.exists()) {
          final curRaw =
              int.tryParse((await curFile.readAsString()).trim()) ?? 0;
          final maxRaw =
              int.tryParse((await maxFile.readAsString()).trim()) ?? 1;
          max = maxRaw;
          current = curRaw.clamp(0, maxRaw);
        }
      }

      final percent =
          max > 0 ? ((current / max) * 100).round().clamp(0, 100) : 0;
      final status = BrightnessStatus(
        current: percent,
        max: 100,
        autoEnabled: false,
        available: true,
      );
      // #region debug-point D:brightness-service-status
      (() async {
        try {
          var debugServerUrl = 'http://198.18.0.1:7778/event';
          var debugSessionId = 'display-settings-crash';
          try {
            final env =
                await File('.dbg/display-settings-crash.env').readAsString();
            for (final line in env.split('\n')) {
              if (line.startsWith('DEBUG_SERVER_URL=')) {
                debugServerUrl = line.substring('DEBUG_SERVER_URL='.length);
              } else if (line.startsWith('DEBUG_SESSION_ID=')) {
                debugSessionId = line.substring('DEBUG_SESSION_ID='.length);
              }
            }
          } catch (_) {}
          final client = HttpClient();
          final req = await client.postUrl(Uri.parse(debugServerUrl));
          req.headers.contentType = ContentType.json;
          req.write(
            jsonEncode({
              'sessionId': debugSessionId,
              'runId': 'pre-fix',
              'hypothesisId': 'D',
              'location': 'lib/services/native_brightness_service.dart:181',
              'msg': '[DEBUG] brightness getStatus resolved',
              'data': {
                'current': status.current,
                'max': status.max,
                'available': status.available,
              },
              'ts': DateTime.now().millisecondsSinceEpoch,
            }),
          );
          await req.close();
          client.close();
        } catch (_) {}
      })();
      // #endregion
      _setStatus(status);
      return status;
    } catch (error, stackTrace) {
      _handleError(error, stackTrace);
      return null;
    }
  }

  Future<bool> setBrightness(int percent) async {
    if (!_initialized) {
      await initialize();
    }

    percent = percent.clamp(0, 100);

    if (_backlightPath == null) {
      developer.log('没有可用的亮度后端', name: 'NativeBrightnessService');
      return false;
    }

    try {
      if (_backlightPath != null) {
        final maxFile = File('$_backlightPath/max_brightness');
        final curFile = File('$_backlightPath/brightness');
        if (await maxFile.exists() && await curFile.exists()) {
          final maxRaw =
              int.tryParse((await maxFile.readAsString()).trim()) ?? 1;
          final newRaw = ((percent / 100.0) * maxRaw).round().clamp(0, maxRaw);
          await curFile.writeAsString('$newRaw');
        } else {
          return false;
        }
      }

      await getStatus();
      return true;
    } catch (error, stackTrace) {
      _handleError(error, stackTrace);
      return false;
    }
  }

  Future<void> dispose() async {
    _pollTimer?.cancel();
    _pollTimer = null;
    _initialized = false;
    await _statusController.close();
  }

  void _setStatus(BrightnessStatus status) {
    _currentStatus = status;
    if (!_statusController.isClosed) {
      _statusController.add(status);
    }
  }

  void _handleError(Object error, [StackTrace? stackTrace]) {
    // #region debug-point D:brightness-service-error
    (() async {
      try {
        var debugServerUrl = 'http://198.18.0.1:7778/event';
        var debugSessionId = 'display-settings-crash';
        try {
          final env =
              await File('.dbg/display-settings-crash.env').readAsString();
          for (final line in env.split('\n')) {
            if (line.startsWith('DEBUG_SERVER_URL=')) {
              debugServerUrl = line.substring('DEBUG_SERVER_URL='.length);
            } else if (line.startsWith('DEBUG_SESSION_ID=')) {
              debugSessionId = line.substring('DEBUG_SESSION_ID='.length);
            }
          }
        } catch (_) {}
        final client = HttpClient();
        final req = await client.postUrl(Uri.parse(debugServerUrl));
        req.headers.contentType = ContentType.json;
        req.write(
          jsonEncode({
            'sessionId': debugSessionId,
            'runId': 'pre-fix',
            'hypothesisId': 'D',
            'location': 'lib/services/native_brightness_service.dart:248',
            'msg': '[DEBUG] brightness service error handled',
            'data': {'error': error.toString()},
            'ts': DateTime.now().millisecondsSinceEpoch,
          }),
        );
        await req.close();
        client.close();
      } catch (_) {}
    })();
    // #endregion
    developer.log(
      '亮度服务不可用: $error',
      name: 'NativeBrightnessService',
      error: error,
      stackTrace: stackTrace,
    );
    _currentStatus = _currentStatus.copyWith(available: false);
    if (!_statusController.isClosed) {
      _statusController.add(_currentStatus);
    }
  }
}
