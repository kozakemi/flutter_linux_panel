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

  static const int _maxOutputCharacters = 128 * 1024;

  String _output = '';
  int _outputRevision = 0;
  int _outputStartOffset = 0;
  int _outputEndOffset = 0;
  Timer? _notifyTimer;
  Process? _readerProcess;
  RandomAccessFile? _writer;
  Future<void> _pendingWrite = Future<void>.value();
  final _AnsiEscapeFilter _ansiFilter = _AnsiEscapeFilter();
  bool _opening = false;
  int _requestId = 0;

  String? _device;
  int _baudRate = 115200;
  SerialParity _parity = SerialParity.none;
  List<String> _devices = const <String>[];
  DateTime? _lastDeviceScan;

  String get output => _output;
  int get outputRevision => _outputRevision;
  int get outputStartOffset => _outputStartOffset;
  int get outputEndOffset => _outputEndOffset;
  bool get open => _readerProcess != null;
  bool get opening => _opening;
  String? get device => _device;
  int get baudRate => _baudRate;
  SerialParity get parity => _parity;
  List<String> get devices => List<String>.unmodifiable(_devices);

  Future<List<String>> scanDevices({bool force = false}) async {
    final lastScan = _lastDeviceScan;
    if (!force &&
        lastScan != null &&
        DateTime.now().difference(lastScan) < const Duration(seconds: 3)) {
      return devices;
    }
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
      _devices = devices;
      _lastDeviceScan = DateTime.now();
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
      _writer = await File(device).open(mode: FileMode.write);
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
        unawaited(_closeWriter());
        _opening = false;
        _appendSystem('串口已关闭，读取进程退出码: $exitCode');
      }));
    } catch (error) {
      if (requestId != _requestId) return;
      _readerProcess?.kill(ProcessSignal.sigterm);
      _readerProcess = null;
      await _closeWriter();
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

  Future<void> send(String data) {
    if (data.isEmpty) return Future<void>.value();
    if (!open || _writer == null) {
      throw StateError('串口尚未打开');
    }
    final bytes = utf8.encode(data);
    _pendingWrite = _pendingWrite.catchError((_) {}).then((_) async {
      final writer = _writer;
      if (!open || writer == null) throw StateError('串口已经关闭');
      try {
        await writer.writeFrom(bytes);
      } catch (error) {
        _appendSystem('发送失败：$error');
        rethrow;
      }
    });
    return _pendingWrite;
  }

  void clearOutput() {
    _output = '';
    _outputStartOffset = _outputEndOffset;
    _scheduleNotify();
  }

  String outputAfter(int offset) {
    if (offset <= _outputStartOffset) return _output;
    if (offset >= _outputEndOffset) return '';
    return _output.substring(offset - _outputStartOffset);
  }

  void _appendData(String data) {
    if (data.isEmpty) return;
    final visible = _ansiFilter.convert(data);
    if (visible.isNotEmpty) _append(visible);
  }

  void _appendSystem(String message) {
    _append('\n[系统] $message\n');
  }

  void _append(String value) {
    _output += value;
    _outputEndOffset += value.length;
    if (_output.length > _maxOutputCharacters) {
      final removed = _output.length - _maxOutputCharacters;
      _output = _output.substring(removed);
      _outputStartOffset += removed;
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

  Future<void> _closeWriter() async {
    final writer = _writer;
    _writer = null;
    if (writer != null) {
      try {
        await writer.close();
      } catch (_) {}
    }
  }
}

/// Removes terminal control sequences that a plain-text preview cannot render.
///
/// The parser keeps its state between serial chunks because an ANSI sequence
/// such as ESC[?2004h may be split across multiple reads.
class _AnsiEscapeFilter {
  static const int _text = 0;
  static const int _escape = 1;
  static const int _csi = 2;
  static const int _osc = 3;
  static const int _oscEscape = 4;

  int _state = _text;

  String convert(String input) {
    final output = StringBuffer();
    for (final rune in input.runes) {
      switch (_state) {
        case _text:
          if (rune == 0x1b) {
            _state = _escape;
          } else if (rune == 0x9b) {
            _state = _csi;
          } else {
            output.writeCharCode(rune);
          }
        case _escape:
          if (rune == 0x5b) {
            _state = _csi;
          } else if (rune == 0x5d) {
            _state = _osc;
          } else if (rune == 0x1b) {
            _state = _escape;
          } else {
            // Other ANSI escape commands consist of ESC plus this byte.
            _state = _text;
          }
        case _csi:
          // A CSI command ends with a byte in the range 0x40–0x7e.
          if (rune >= 0x40 && rune <= 0x7e) _state = _text;
        case _osc:
          if (rune == 0x07) {
            _state = _text;
          } else if (rune == 0x1b) {
            _state = _oscEscape;
          }
        case _oscEscape:
          _state = rune == 0x5c ? _text : _osc;
      }
    }
    return output.toString();
  }
}
