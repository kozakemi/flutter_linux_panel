import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

enum SerialParity {
  none('无校验'),
  odd('奇校验'),
  even('偶校验');

  const SerialParity(this.label);
  final String label;
}

class SerialPortService extends ChangeNotifier {
  SerialPortService._();

  static final SerialPortService instance = SerialPortService._();

  final List<String> _output = <String>[];
  Process? _readerProcess;
  bool _opening = false;
  int _requestId = 0;

  String? _device;
  int _baudRate = 115200;
  SerialParity _parity = SerialParity.none;

  List<String> get output => List<String>.unmodifiable(_output);
  bool get open => _readerProcess != null;
  bool get opening => _opening;
  String? get device => _device;
  int get baudRate => _baudRate;
  SerialParity get parity => _parity;

  Future<List<String>> scanDevices() async {
    try {
      final entries = await Directory('/dev').list().toList();
      final devices = entries
          .whereType<File>()
          .map((entry) => entry.path)
          .where(
            (path) => RegExp(
              r'^/dev/tty(?:S|USB|ACM|AMA|XRUSB|FIQ)\d+$',
            ).hasMatch(path),
          )
          .toList()
        ..sort();
      return devices;
    } catch (error) {
      _appendSystem('扫描串口失败：$error');
      return const <String>[];
    }
  }

  Future<void> openPort({
    required String device,
    required int baudRate,
    required SerialParity parity,
  }) async {
    if (open || opening) return;

    final requestId = ++_requestId;
    _opening = true;
    notifyListeners();
    _appendSystem(
      '正在打开 $device，$baudRate baud，${parity.label}',
    );

    try {
      final parityArguments = switch (parity) {
        SerialParity.none => const <String>['-parenb'],
        SerialParity.odd => const <String>['parenb', 'parodd'],
        SerialParity.even => const <String>['parenb', '-parodd'],
      };
      final sttyArguments = <String>[
        '-F',
        device,
        baudRate.toString(),
        'raw',
        '-echo',
        'cs8',
        '-cstopb',
        ...parityArguments,
      ];
      final configureResult = await Process.run(
        'stty',
        sttyArguments,
        runInShell: false,
      );
      if (requestId != _requestId) return;
      if (configureResult.exitCode != 0) {
        final error = configureResult.stderr.toString().trim();
        throw ProcessException(
          'stty',
          sttyArguments,
          error.isEmpty ? '串口配置失败' : error,
          configureResult.exitCode,
        );
      }

      final process = await Process.start(
        '/bin/cat',
        <String>[device],
        mode: ProcessStartMode.normal,
        runInShell: false,
      );
      if (requestId != _requestId) {
        process.kill(ProcessSignal.sigterm);
        return;
      }

      _readerProcess = process;
      _device = device;
      _baudRate = baudRate;
      _parity = parity;
      _opening = false;
      notifyListeners();
      _appendSystem('串口已打开，读取进程 PID: ${process.pid}');

      process.stdout.transform(const Utf8Decoder(allowMalformed: true)).listen(
            _appendData,
            onError: (Object error) => _appendSystem('读取串口失败：$error'),
          );
      process.stderr
          .transform(const Utf8Decoder(allowMalformed: true))
          .transform(const LineSplitter())
          .listen(
            (line) => _appendSystem('[stderr] $line'),
            onError: (Object error) => _appendSystem('读取错误输出失败：$error'),
          );

      unawaited(process.exitCode.then((exitCode) {
        if (_readerProcess != process) return;
        _readerProcess = null;
        _opening = false;
        _appendSystem('串口已关闭，读取进程退出码: $exitCode');
      }));
    } catch (error) {
      if (requestId != _requestId) return;
      _opening = false;
      _appendSystem('打开串口失败：$error');
    }
  }

  void closePort() {
    ++_requestId;
    final process = _readerProcess;
    if (process == null) {
      if (_opening) {
        _opening = false;
        _appendSystem('已取消打开串口');
      }
      return;
    }
    final signalSent = process.kill(ProcessSignal.sigterm);
    _appendSystem(signalSent ? '正在关闭串口…' : '无法停止串口读取进程');
  }

  void clearOutput() {
    _output.clear();
    notifyListeners();
  }

  void _appendData(String data) {
    if (data.isEmpty) return;
    _output.add(data);
    _trimOutput();
    notifyListeners();
  }

  void _appendSystem(String message) {
    _output.add('\n[系统] $message\n');
    _trimOutput();
    notifyListeners();
  }

  void _trimOutput() {
    if (_output.length > 4000) {
      _output.removeRange(0, _output.length - 4000);
    }
  }
}
