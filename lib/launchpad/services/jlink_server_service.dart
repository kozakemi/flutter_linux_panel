import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

class JLinkServerService extends ChangeNotifier {
  JLinkServerService._();

  static final JLinkServerService instance = JLinkServerService._();

  static const String executable = '/opt/SEGGER/JLink/JLinkRemoteServerCLExe';
  static const int port = 19020;

  static const int _maxLogCharacters = 128 * 1024;

  final List<String> _logs = <String>[];
  int _logCharacters = 0;
  Timer? _notifyTimer;
  final List<String> _addresses = <String>[];
  Process? _process;
  bool _starting = false;
  bool _addressesLoading = false;
  int _processRequestId = 0;

  List<String> get logs => UnmodifiableListView(_logs);
  List<String> get addresses => UnmodifiableListView(_addresses);
  bool get running => _process != null;
  bool get starting => _starting;
  int? get processId => _process?.pid;

  Future<void> loadAddresses() async {
    if (_addressesLoading || _addresses.isNotEmpty) return;
    _addressesLoading = true;
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
        includeLinkLocal: false,
      );
      _addresses
        ..clear()
        ..addAll([
          for (final interface in interfaces)
            for (final address in interface.addresses)
              '${interface.name}: ${address.address}',
        ]);
      notifyListeners();
    } catch (error) {
      _appendLog('获取本机 IP 失败：$error');
    } finally {
      _addressesLoading = false;
    }
  }

  Future<void> start() async {
    if (running || starting) return;

    final requestId = ++_processRequestId;
    _starting = true;
    notifyListeners();
    _appendLog(r'$ ' '$executable -Port $port');

    try {
      if (!await File(executable).exists()) {
        throw const FileSystemException('找不到 J-Link Remote Server');
      }
      final process = await Process.start(
        executable,
        const <String>['-Port', '19020'],
        mode: ProcessStartMode.normal,
        runInShell: false,
      );
      if (requestId != _processRequestId) {
        process.kill(ProcessSignal.sigterm);
        return;
      }

      _process = process;
      _starting = false;
      notifyListeners();
      _appendLog('J-Link Remote Server 已启动，PID: ${process.pid}');

      process.stdout
          .transform(const Utf8Decoder(allowMalformed: true))
          .transform(const LineSplitter())
          .listen(
            _appendLog,
            onError: (Object error) => _appendLog('读取 stdout 失败：$error'),
          );
      process.stderr
          .transform(const Utf8Decoder(allowMalformed: true))
          .transform(const LineSplitter())
          .listen(
            (line) => _appendLog('[stderr] $line'),
            onError: (Object error) => _appendLog('读取 stderr 失败：$error'),
          );

      unawaited(process.exitCode.then((exitCode) {
        if (_process != process) return;
        _process = null;
        _starting = false;
        _appendLog('J-Link Remote Server 已退出，退出码: $exitCode');
      }));
    } catch (error) {
      if (requestId != _processRequestId) return;
      _starting = false;
      _appendLog('启动失败：$error');
    }
  }

  void stop() {
    ++_processRequestId;
    final process = _process;
    if (process == null) {
      if (_starting) {
        _starting = false;
        _appendLog('已取消启动');
      }
      return;
    }
    final signalSent = process.kill(ProcessSignal.sigterm);
    _appendLog(signalSent ? '正在停止服务…' : '无法向服务发送停止信号');
  }

  void clearLogs() {
    _logs.clear();
    _logCharacters = 0;
    notifyListeners();
  }

  void _appendLog(String message) {
    _logs.add(message);
    _logCharacters += message.length;
    while (_logCharacters > _maxLogCharacters && _logs.length > 1) {
      _logCharacters -= _logs.removeAt(0).length;
    }
    _notifyTimer ??= Timer(const Duration(milliseconds: 50), () {
      _notifyTimer = null;
      notifyListeners();
    });
  }
}
