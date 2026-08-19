import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

class TailscaleService extends ChangeNotifier {
  TailscaleService._();

  static final TailscaleService instance = TailscaleService._();

  static const int _maxLogCharacters = 64 * 1024;
  static final RegExp _loginUrlPattern = RegExp(r'https://[^\s\x1b]+');

  final List<String> _logs = <String>[];
  int _logCharacters = 0;
  bool _refreshing = false;
  bool _busy = false;
  bool _installed = true;
  bool _daemonActive = false;
  String _backendState = '';
  String _hostName = '';
  String _dnsName = '';
  String _tailnetName = '';
  List<String> _addresses = const <String>[];
  String _loginUrl = '';
  String? _error;
  Process? _authProcess;
  String _authOutputTail = '';

  UnmodifiableListView<String> get logs => UnmodifiableListView(_logs);
  bool get refreshing => _refreshing;
  bool get busy => _busy;
  bool get installed => _installed;
  bool get daemonActive => _daemonActive;
  String get backendState => _backendState;
  String get hostName => _hostName;
  String get dnsName => _dnsName;
  String get tailnetName => _tailnetName;
  List<String> get addresses => List<String>.unmodifiable(_addresses);
  String get loginUrl => _loginUrl;
  String? get error => _error;
  bool get authPending => _authProcess != null;
  bool get connected => _backendState == 'Running';
  bool get needsLogin => _backendState == 'NeedsLogin';

  Future<void> refresh() async {
    if (_refreshing) return;
    _refreshing = true;
    notifyListeners();
    try {
      final daemon = await _runProcess(
        'systemctl',
        const <String>['is-active', 'tailscaled.service'],
        timeout: const Duration(seconds: 3),
      );
      _daemonActive = daemon.exitCode == 0 && daemon.stdout.trim() == 'active';

      final result = await _runProcess(
        'tailscale',
        const <String>['status', '--json'],
        timeout: const Duration(seconds: 5),
      );
      _installed = true;
      if (result.exitCode != 0) {
        _backendState = _daemonActive ? 'Unavailable' : 'Stopped';
        _error = _clean(result.stderr.isEmpty ? result.stdout : result.stderr);
        return;
      }
      final value = jsonDecode(result.stdout);
      if (value is! Map<String, dynamic>) {
        throw const FormatException('tailscale status 返回格式不正确');
      }
      _backendState = value['BackendState'] as String? ?? '';
      _addresses = (value['TailscaleIPs'] as List? ?? const <Object>[])
          .whereType<String>()
          .toList(growable: false);
      final self = value['Self'];
      if (self is Map<String, dynamic>) {
        _hostName = self['HostName'] as String? ?? '';
        _dnsName = (self['DNSName'] as String? ?? '').replaceFirst(
          RegExp(r'\.$'),
          '',
        );
      }
      final currentTailnet = value['CurrentTailnet'];
      if (currentTailnet is Map<String, dynamic>) {
        _tailnetName = currentTailnet['Name'] as String? ??
            currentTailnet['MagicDNSSuffix'] as String? ??
            '';
      }
      _error = null;
      if (connected) _loginUrl = '';
    } on ProcessException catch (error) {
      _installed = false;
      _daemonActive = false;
      _backendState = '';
      _error = '找不到 tailscale：${error.message}';
    } catch (error) {
      _error = '读取 Tailscale 状态失败：$error';
    } finally {
      _refreshing = false;
      notifyListeners();
    }
  }

  Future<void> startDaemon() => _runAction(
        '启动 tailscaled',
        'systemctl',
        const <String>['start', 'tailscaled.service'],
      );

  Future<void> stopDaemon() => _runAction(
        '停止 tailscaled',
        'systemctl',
        const <String>['stop', 'tailscaled.service'],
      );

  Future<void> connect() => _startAuthCommand('up');

  Future<void> login() => _startAuthCommand('login');

  Future<void> disconnect() => _runAction(
        '断开 Tailnet',
        'tailscale',
        const <String>['down'],
      );

  Future<void> logout() => _runAction(
        '退出 Tailscale 登录',
        'tailscale',
        const <String>['logout'],
      );

  Future<void> _runAction(
    String label,
    String executable,
    List<String> arguments,
  ) async {
    if (_busy) return;
    _busy = true;
    _error = null;
    _appendLog(r'$ ' '$executable ${arguments.join(' ')}');
    notifyListeners();
    try {
      final result = await _runProcess(
        executable,
        arguments,
        timeout: const Duration(seconds: 15),
      );
      final output = _clean(
        result.stderr.isEmpty ? result.stdout : result.stderr,
      );
      if (output.isNotEmpty) _appendLog(output);
      if (result.exitCode != 0) {
        _error = '$label失败${output.isEmpty ? '' : '：$output'}';
      } else {
        _appendLog('$label完成');
      }
    } on ProcessException catch (error) {
      _installed = false;
      _error = '$label失败：${error.message}';
    } catch (error) {
      _error = '$label失败：$error';
    } finally {
      _busy = false;
      await refresh();
    }
  }

  Future<void> _startAuthCommand(String command) async {
    if (_busy || _authProcess != null) return;
    _busy = true;
    _error = null;
    _loginUrl = '';
    _authOutputTail = '';
    _appendLog(r'$ tailscale ' '$command');
    notifyListeners();
    try {
      if (!_daemonActive) {
        final daemon = await _runProcess(
          'systemctl',
          const <String>['start', 'tailscaled.service'],
          timeout: const Duration(seconds: 10),
        );
        if (daemon.exitCode != 0) {
          throw ProcessException(
            'systemctl',
            const <String>['start', 'tailscaled.service'],
            _clean(daemon.stderr),
            daemon.exitCode,
          );
        }
      }
      final process = await Process.start(
        'tailscale',
        <String>[command],
        mode: ProcessStartMode.normal,
        runInShell: false,
      );
      _authProcess = process;
      _busy = false;
      notifyListeners();
      process.stdout
          .transform(const Utf8Decoder(allowMalformed: true))
          .listen(_handleAuthOutput);
      process.stderr
          .transform(const Utf8Decoder(allowMalformed: true))
          .listen(_handleAuthOutput);
      unawaited(process.exitCode.then((exitCode) async {
        if (_authProcess != process) return;
        _authProcess = null;
        _appendLog('$command 已结束，退出码：$exitCode');
        if (exitCode != 0 && _loginUrl.isEmpty) {
          _error = '$command 执行失败，请查看日志';
        }
        await refresh();
      }));
    } on ProcessException catch (error) {
      _busy = false;
      _authProcess = null;
      _installed = error.executable != 'tailscale';
      _error = '$command 启动失败：${error.message}';
      notifyListeners();
    } catch (error) {
      _busy = false;
      _authProcess = null;
      _error = '$command 启动失败：$error';
      notifyListeners();
    }
  }

  void cancelAuthentication() {
    final process = _authProcess;
    if (process == null) return;
    process.kill(ProcessSignal.sigterm);
    _appendLog('已取消当前登录流程');
  }

  void clearLogs() {
    _logs.clear();
    _logCharacters = 0;
    notifyListeners();
  }

  void _handleAuthOutput(String chunk) {
    final clean = _clean(chunk);
    if (clean.isNotEmpty) _appendLog(clean);
    _authOutputTail = '$_authOutputTail$clean';
    if (_authOutputTail.length > 4096) {
      _authOutputTail =
          _authOutputTail.substring(_authOutputTail.length - 4096);
    }
    final match = _loginUrlPattern.firstMatch(_authOutputTail);
    if (match != null) {
      _loginUrl = match.group(0)!.replaceFirst(RegExp(r'[,.;]+$'), '');
      notifyListeners();
    }
  }

  Future<_ProcessResult> _runProcess(
    String executable,
    List<String> arguments, {
    required Duration timeout,
  }) async {
    final process = await Process.start(
      executable,
      arguments,
      mode: ProcessStartMode.normal,
      runInShell: false,
    );
    final stdoutFuture = process.stdout
        .transform(const Utf8Decoder(allowMalformed: true))
        .join();
    final stderrFuture = process.stderr
        .transform(const Utf8Decoder(allowMalformed: true))
        .join();
    int exitCode;
    try {
      exitCode = await process.exitCode.timeout(timeout);
    } on TimeoutException {
      process.kill(ProcessSignal.sigterm);
      throw TimeoutException('$executable 执行超时', timeout);
    }
    return _ProcessResult(
      exitCode,
      await stdoutFuture,
      await stderrFuture,
    );
  }

  String _clean(String value) => value
      .replaceAll(RegExp(r'\x1b\[[0-9;?]*[A-Za-z]'), '')
      .replaceAll('\r', '')
      .trim();

  void _appendLog(String message) {
    if (message.isEmpty) return;
    for (final line in message.split('\n')) {
      if (line.trim().isEmpty) continue;
      _logs.add(line);
      _logCharacters += line.length;
    }
    while (_logCharacters > _maxLogCharacters && _logs.length > 1) {
      _logCharacters -= _logs.removeAt(0).length;
    }
    notifyListeners();
  }
}

class _ProcessResult {
  const _ProcessResult(this.exitCode, this.stdout, this.stderr);

  final int exitCode;
  final String stdout;
  final String stderr;
}
