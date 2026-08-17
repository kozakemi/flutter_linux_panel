import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

class JLinkRttService extends ChangeNotifier {
  JLinkRttService._();

  static final JLinkRttService instance = JLinkRttService._();

  static const String executable = '/opt/SEGGER/JLink/JLinkGDBServerCLExe';
  static const int gdbPort = 19021;
  static const int rttPort = 19022;
  static const int _maxOutputCharacters = 128 * 1024;

  Process? _process;
  Socket? _socket;
  Timer? _notifyTimer;
  bool _starting = false;
  int _requestId = 0;
  String _output = '';
  int _outputRevision = 0;
  String _device = '';
  String _interface = 'SWD';
  int _speed = 4000;

  bool get running => _process != null;
  bool get connected => _socket != null;
  bool get starting => _starting;
  String get output => _output;
  int get outputRevision => _outputRevision;
  String get device => _device;
  String get interface => _interface;
  int get speed => _speed;

  Future<void> start({
    required String device,
    required String interface,
    required int speed,
  }) async {
    if (running || starting) return;
    final normalizedDevice = device.trim();
    if (normalizedDevice.isEmpty) {
      _appendSystem('必须填写目标芯片型号，例如 STM32F407VG');
      return;
    }

    final requestId = ++_requestId;
    _starting = true;
    _device = normalizedDevice;
    _interface = interface;
    _speed = speed;
    notifyListeners();
    final arguments = <String>[
      '-singlerun',
      '-nogui',
      '-device',
      normalizedDevice,
      '-if',
      interface,
      '-speed',
      '$speed',
      '-port',
      '$gdbPort',
      '-RTTTelnetPort',
      '$rttPort',
    ];
    _appendSystem('$executable ${arguments.join(' ')}');

    try {
      if (!await File(executable).exists()) {
        throw const FileSystemException('找不到 J-Link GDB Server');
      }
      final process = await Process.start(
        executable,
        arguments,
        mode: ProcessStartMode.normal,
        runInShell: false,
      );
      if (requestId != _requestId) {
        process.kill(ProcessSignal.sigterm);
        return;
      }
      _process = process;
      _starting = false;
      notifyListeners();
      _appendSystem('GDB Server 已启动，PID: ${process.pid}');

      process.stdout
          .transform(const Utf8Decoder(allowMalformed: true))
          .listen(_append);
      process.stderr
          .transform(const Utf8Decoder(allowMalformed: true))
          .listen((value) => _append('[stderr] $value'));
      unawaited(process.exitCode.then((exitCode) {
        if (_process != process) return;
        _process = null;
        _starting = false;
        _socket?.destroy();
        _socket = null;
        _appendSystem('GDB Server 已退出，退出码: $exitCode');
      }));
      unawaited(_connectRtt(requestId));
    } catch (error) {
      if (requestId != _requestId) return;
      _process = null;
      _starting = false;
      _appendSystem('启动失败：$error');
    }
  }

  Future<void> _connectRtt(int requestId) async {
    for (var attempt = 0; attempt < 20; attempt++) {
      if (requestId != _requestId || _process == null) return;
      try {
        final socket = await Socket.connect(
          InternetAddress.loopbackIPv4,
          rttPort,
          timeout: const Duration(seconds: 1),
        );
        if (requestId != _requestId) {
          socket.destroy();
          return;
        }
        _socket = socket;
        _appendSystem('RTT 通道已连接，可以收发数据');
        socket
            .cast<List<int>>()
            .transform(const Utf8Decoder(allowMalformed: true))
            .listen(
              _append,
              onError: (Object error) => _appendSystem('RTT 读取失败：$error'),
              onDone: () {
                if (_socket == socket) {
                  _socket = null;
                  _appendSystem('RTT 通道已断开');
                }
              },
            );
        notifyListeners();
        return;
      } catch (_) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
    }
    _appendSystem('RTT 端口连接超时，请检查芯片型号、接线和 RTT 配置');
  }

  void stop() {
    ++_requestId;
    _socket?.destroy();
    _socket = null;
    final process = _process;
    _process = null;
    _starting = false;
    if (process != null) {
      process.kill(ProcessSignal.sigterm);
    }
    _appendSystem('正在停止 J-Link RTT…');
  }

  void send(String data) {
    if (data.isEmpty) return;
    final socket = _socket;
    if (socket == null) {
      throw StateError('RTT 通道尚未连接');
    }
    socket.add(utf8.encode(data));
  }

  void clearOutput() {
    _output = '';
    _scheduleNotify();
  }

  void _appendSystem(String message) => _append('\n[系统] $message\n');

  void _append(String value) {
    if (value.isEmpty) return;
    _output += value;
    if (_output.length > _maxOutputCharacters) {
      _output = _output.substring(_output.length - _maxOutputCharacters);
    }
    _scheduleNotify();
  }

  void _scheduleNotify() {
    _outputRevision++;
    _notifyTimer ??= Timer(const Duration(milliseconds: 50), () {
      _notifyTimer = null;
      notifyListeners();
    });
  }
}
