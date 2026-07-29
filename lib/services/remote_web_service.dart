import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'wallpaper_service.dart';

class RemoteWebService extends ChangeNotifier {
  RemoteWebService._();

  static final RemoteWebService instance = RemoteWebService._();

  static const int port = 19080;
  static const int _maxUploadBytes = 20 * 1024 * 1024;
  static const String _enabledKey = 'remote_web_enabled';

  HttpServer? _server;
  bool _starting = false;
  String? _error;
  String _token = '';
  List<String> _addresses = const <String>[];

  bool get enabled => _server != null;
  bool get starting => _starting;
  String? get error => _error;
  List<String> get addresses => List<String>.unmodifiable(_addresses);
  String? get primaryUrl =>
      _addresses.isEmpty ? null : _urlForAddress(_addresses.first);

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_enabledKey) ?? false) {
      await start();
    } else {
      await refreshAddresses();
    }
  }

  Future<void> setEnabled(bool value) async {
    if (value) {
      await start();
    } else {
      await stop();
    }
  }

  Future<void> start() async {
    if (enabled || starting) return;
    _starting = true;
    _error = null;
    notifyListeners();
    try {
      _token = _generateToken();
      _server = await HttpServer.bind(
        InternetAddress.anyIPv4,
        port,
        shared: true,
      );
      unawaited(_serve(_server!));
      await refreshAddresses();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_enabledKey, true);
    } catch (error) {
      _server = null;
      _error = '启动失败：$error';
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_enabledKey, false);
    } finally {
      _starting = false;
      notifyListeners();
    }
  }

  Future<void> stop() async {
    final server = _server;
    _server = null;
    _token = '';
    if (server != null) {
      await server.close(force: true);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, false);
    notifyListeners();
  }

  Future<void> refreshAddresses() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
        includeLinkLocal: false,
      );
      final wireless = <String>[];
      final others = <String>[];
      for (final interface in interfaces) {
        final target = _isWireless(interface.name) ? wireless : others;
        target.addAll(interface.addresses.map((address) => address.address));
      }
      _addresses = <String>[...wireless, ...others];
      notifyListeners();
    } catch (error) {
      _error = '获取本机地址失败：$error';
      notifyListeners();
    }
  }

  Future<void> _serve(HttpServer server) async {
    try {
      await for (final request in server) {
        unawaited(_handleRequest(request));
      }
    } catch (_) {
      // 服务被主动关闭时会结束请求循环。
    }
  }

  Future<void> _handleRequest(HttpRequest request) async {
    try {
      if (request.uri.queryParameters['token'] != _token || _token.isEmpty) {
        await _sendText(request.response, HttpStatus.forbidden, '访问链接无效');
        return;
      }

      if (request.method == 'GET' && request.uri.path == '/') {
        request.response.headers.contentType = ContentType.html;
        request.response.write(_webPage);
        await request.response.close();
        return;
      }
      if (request.method == 'POST' && request.uri.path == '/api/wallpaper') {
        await _handleWallpaperUpload(request);
        return;
      }
      await _sendText(request.response, HttpStatus.notFound, '未找到');
    } catch (error) {
      if (!request.response.headers.contentType.toString().contains('json')) {
        request.response.headers.contentType = ContentType.json;
      }
      request.response.statusCode = HttpStatus.internalServerError;
      request.response.write(jsonEncode({'ok': false, 'error': '$error'}));
      await request.response.close();
    }
  }

  Future<void> _handleWallpaperUpload(HttpRequest request) async {
    final contentType = request.headers.contentType?.mimeType ?? '';
    final extension = switch (contentType) {
      'image/jpeg' => 'jpg',
      'image/png' => 'png',
      'image/webp' => 'webp',
      'image/gif' => 'gif',
      'image/bmp' => 'bmp',
      _ => null,
    };
    if (extension == null) {
      await _sendJson(
        request.response,
        HttpStatus.unsupportedMediaType,
        {'ok': false, 'error': '仅支持 JPG、PNG、WebP、GIF 或 BMP 图片'},
      );
      return;
    }
    if (request.contentLength > _maxUploadBytes) {
      await _sendJson(
        request.response,
        HttpStatus.requestEntityTooLarge,
        {'ok': false, 'error': '图片不能超过 20 MB'},
      );
      return;
    }

    final builder = BytesBuilder(copy: false);
    var length = 0;
    await for (final chunk in request) {
      length += chunk.length;
      if (length > _maxUploadBytes) {
        await _sendJson(
          request.response,
          HttpStatus.requestEntityTooLarge,
          {'ok': false, 'error': '图片不能超过 20 MB'},
        );
        return;
      }
      builder.add(chunk);
    }
    if (length == 0) {
      await _sendJson(
        request.response,
        HttpStatus.badRequest,
        {'ok': false, 'error': '没有收到图片数据'},
      );
      return;
    }

    final home = Platform.environment['HOME'] ?? Directory.current.path;
    final directory = Directory('$home/.config/demo1/wallpapers');
    await directory.create(recursive: true);
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final file =
        File('${directory.path}/remote_wallpaper_$timestamp.$extension');
    await file.writeAsBytes(builder.takeBytes(), flush: true);
    await WallpaperService.instance.setWallpaper(file.path);
    await _sendJson(
      request.response,
      HttpStatus.ok,
      {'ok': true, 'message': '壁纸已更新'},
    );
  }

  Future<void> _sendText(
    HttpResponse response,
    int status,
    String message,
  ) async {
    response.statusCode = status;
    response.headers.contentType = ContentType.text;
    response.write(message);
    await response.close();
  }

  Future<void> _sendJson(
    HttpResponse response,
    int status,
    Map<String, Object> body,
  ) async {
    response.statusCode = status;
    response.headers.contentType = ContentType.json;
    response.write(jsonEncode(body));
    await response.close();
  }

  String _urlForAddress(String address) =>
      'http://$address:$port/?token=$_token';

  bool _isWireless(String name) {
    final lower = name.toLowerCase();
    return lower.startsWith('wlan') || lower.startsWith('wlp');
  }

  String _generateToken() {
    const characters = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final random = Random.secure();
    return List<String>.generate(
      4,
      (_) => characters[random.nextInt(characters.length)],
    ).join();
  }

  static const String _webPage = r'''
<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title>设备壁纸设置</title>
  <style>
    :root { color-scheme: light dark; font-family: system-ui, sans-serif; }
    body { margin: 0; min-height: 100vh; display: grid; place-items: center;
      background: #f4f6f8; color: #1b1b1f; }
    main { width: min(88vw, 520px); padding: 28px; border-radius: 24px;
      background: white; box-shadow: 0 12px 40px #0002; }
    h1 { margin: 0 0 8px; font-size: 24px; }
    p { color: #5f6368; }
    .drop { display: grid; place-items: center; min-height: 220px;
      border: 2px dashed #9aa0a6; border-radius: 18px; overflow: hidden; }
    img { display: none; width: 100%; max-height: 320px; object-fit: contain; }
    input { max-width: 90%; }
    button { width: 100%; margin-top: 18px; padding: 14px; border: 0;
      border-radius: 999px; font-size: 16px; background: #1967d2; color: white; }
    button:disabled { opacity: .5; }
    #status { min-height: 24px; margin-top: 12px; }
    @media (prefers-color-scheme: dark) {
      body { background: #111318; color: #e3e2e6; }
      main { background: #1b1b1f; } p { color: #c4c7c5; }
    }
  </style>
</head>
<body>
<main>
  <h1>壁纸设置</h1>
  <p>选择图片后上传，开发板主界面会立即更新。</p>
  <label class="drop">
    <span id="hint">点击选择 JPG、PNG、WebP、GIF 或 BMP</span>
    <img id="preview" alt="壁纸预览">
    <input id="file" type="file" accept="image/jpeg,image/png,image/webp,image/gif,image/bmp">
  </label>
  <button id="upload" disabled>应用为壁纸</button>
  <div id="status"></div>
</main>
<script>
const file = document.querySelector('#file');
const preview = document.querySelector('#preview');
const hint = document.querySelector('#hint');
const upload = document.querySelector('#upload');
const status = document.querySelector('#status');
file.onchange = () => {
  const selected = file.files[0];
  upload.disabled = !selected;
  if (!selected) return;
  preview.src = URL.createObjectURL(selected);
  preview.style.display = 'block';
  hint.style.display = 'none';
};
upload.onclick = async () => {
  const selected = file.files[0];
  if (!selected) return;
  upload.disabled = true;
  status.textContent = '正在上传…';
  try {
    const response = await fetch('/api/wallpaper' + location.search, {
      method: 'POST', headers: {'Content-Type': selected.type}, body: selected
    });
    const result = await response.json();
    if (!response.ok || !result.ok) throw new Error(result.error || '上传失败');
    status.textContent = '壁纸已更新';
  } catch (error) {
    status.textContent = error.message;
  } finally {
    upload.disabled = false;
  }
};
</script>
</body>
</html>
''';
}
