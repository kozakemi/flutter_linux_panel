import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'wallpaper_service.dart';
import 'weather_service.dart';
import '../home_assistant/home_assistant_service.dart';
import '../launchpad/services/serial_port_service.dart';
import 'remote_launchpad_service.dart';

class RemoteWebService extends ChangeNotifier {
  RemoteWebService._();

  static final RemoteWebService instance = RemoteWebService._();

  static const int port = 19080;
  static const int discoveryPort = 19081;
  static const int _maxUploadBytes = 20 * 1024 * 1024;
  static const String _enabledKey = 'remote_web_enabled';
  static const String _interfaceKey = 'remote_web_interface';

  HttpServer? _server;
  RawDatagramSocket? _discoverySocket;
  bool _starting = false;
  String? _error;
  String _token = '';
  List<String> _addresses = const <String>[];
  List<RemoteNetworkAddress> _networkAddresses = const <RemoteNetworkAddress>[];
  String? _selectedInterface;
  final Map<String, String> _pairedClients = {};
  String _deviceId = '';

  Future<bool> Function(String clientName, String code)? pairingPrompt;

  bool get enabled => _server != null;
  bool get starting => _starting;
  String? get error => _error;
  List<String> get addresses => List<String>.unmodifiable(_addresses);
  List<RemoteNetworkAddress> get networkAddresses =>
      List<RemoteNetworkAddress>.unmodifiable(_networkAddresses);
  String? get selectedInterface => _selectedInterface;
  String? get primaryUrl =>
      _addresses.isEmpty ? null : _urlForAddress(_addresses.first);

  Future<void> initialize() async {
    await RemoteLaunchpadService.instance.initialize();
    final prefs = await SharedPreferences.getInstance();
    _selectedInterface = prefs.getString(_interfaceKey);
    _deviceId = prefs.getString('remote_device_id') ?? '';
    if (_deviceId.isEmpty) {
      _deviceId = _randomSecret(12);
      await prefs.setString('remote_device_id', _deviceId);
    }
    final paired = prefs.getString('remote_paired_clients');
    if (paired != null) {
      try {
        final value = jsonDecode(paired);
        if (value is Map<String, dynamic>) {
          _pairedClients.addAll(
            value.map((key, value) => MapEntry(key, '$value')),
          );
        }
      } catch (_) {}
    }
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
      await refreshAddresses();
      _token = _generateToken();
      final selectedAddress = _networkAddresses
          .where((item) => item.name == _selectedInterface)
          .firstOrNull;
      _server = await HttpServer.bind(
        selectedAddress?.address ?? InternetAddress.anyIPv4,
        port,
        shared: true,
      );
      await _startDiscovery();
      unawaited(_serve(_server!));
      await refreshAddresses();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_enabledKey, true);
    } catch (error) {
      _discoverySocket?.close();
      _discoverySocket = null;
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
    _discoverySocket?.close();
    _discoverySocket = null;
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
      final wireless = <RemoteNetworkAddress>[];
      final others = <RemoteNetworkAddress>[];
      for (final interface in interfaces) {
        if (interface.addresses.isEmpty) continue;
        final target = _isWireless(interface.name) ? wireless : others;
        target.add(RemoteNetworkAddress(
          name: interface.name,
          address: interface.addresses.first,
        ));
      }
      _networkAddresses = <RemoteNetworkAddress>[...wireless, ...others];
      if (_selectedInterface != null &&
          !_networkAddresses.any((item) => item.name == _selectedInterface)) {
        _selectedInterface = null;
      }
      _addresses = _selectedInterface == null
          ? _networkAddresses.map((item) => item.address.address).toList()
          : _networkAddresses
              .where((item) => item.name == _selectedInterface)
              .map((item) => item.address.address)
              .toList();
      notifyListeners();
    } catch (error) {
      _error = '获取本机地址失败：$error';
      notifyListeners();
    }
  }

  Future<void> setInterface(String? name) async {
    if (_selectedInterface == name) return;
    _selectedInterface = name;
    final prefs = await SharedPreferences.getInstance();
    if (name == null) {
      await prefs.remove(_interfaceKey);
    } else {
      await prefs.setString(_interfaceKey, name);
    }
    final wasEnabled = enabled;
    if (wasEnabled) await stop();
    await refreshAddresses();
    if (wasEnabled) await start();
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
      if (request.method == 'POST' &&
          request.uri.path == '/api/launchpad/pair') {
        await _handlePairRequest(request);
        return;
      }
      if (request.method == 'GET' &&
          request.uri.path == '/api/launchpad/device') {
        await _sendJson(request.response, HttpStatus.ok, {
          'type': 'flutterPanel',
          'deviceId': _deviceId,
          'name': Platform.localHostname,
          'port': port,
        });
        return;
      }
      final query = request.uri.queryParameters;
      final tokenValid = _token.isNotEmpty && query['token'] == _token;
      final pairedValid = query['clientId'] != null &&
          _pairedClients[query['clientId']] == query['secret'];
      if (!tokenValid && !pairedValid) {
        await _sendText(request.response, HttpStatus.forbidden, '访问链接无效');
        return;
      }

      if (request.method == 'GET' &&
          request.uri.path == '/ws/launchpad' &&
          WebSocketTransformer.isUpgradeRequest(request)) {
        final socket = await WebSocketTransformer.upgrade(request);
        RemoteLaunchpadService.instance.accept(socket);
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
      if (request.method == 'GET' &&
          request.uri.path == '/api/weather-config') {
        await _sendWeatherConfiguration(request.response);
        return;
      }
      if (request.method == 'POST' &&
          request.uri.path == '/api/weather-config') {
        await _handleWeatherConfiguration(request);
        return;
      }
      if (request.method == 'GET' && request.uri.path == '/api/ha-config') {
        await _sendHaConfiguration(request.response);
        return;
      }
      if (request.method == 'POST' && request.uri.path == '/api/ha-config') {
        await _handleHaConfiguration(request);
        return;
      }
      if (request.method == 'GET' && request.uri.path == '/api/serial') {
        await _sendSerialStatus(request);
        return;
      }
      if (request.method == 'POST' && request.uri.path == '/api/serial/open') {
        await _handleSerialOpen(request);
        return;
      }
      if (request.method == 'POST' && request.uri.path == '/api/serial/send') {
        await _handleSerialSend(request);
        return;
      }
      if (request.method == 'POST' && request.uri.path == '/api/serial/close') {
        SerialPortService.instance.closePort();
        await _sendJson(
          request.response,
          HttpStatus.ok,
          {'ok': true, 'message': '正在关闭串口'},
        );
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

  Future<void> _startDiscovery() async {
    _discoverySocket?.close();
    final socket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      discoveryPort,
      reuseAddress: true,
    );
    socket.broadcastEnabled = true;
    _discoverySocket = socket;
    socket.listen((event) {
      if (event != RawSocketEvent.read) return;
      final datagram = socket.receive();
      if (datagram == null ||
          utf8.decode(datagram.data, allowMalformed: true) !=
              'FLUTTER_PANEL_DISCOVER_V1') {
        return;
      }
      socket.send(
        utf8.encode(
          jsonEncode({
            'type': 'flutterPanel',
            'deviceId': _deviceId,
            'name': Platform.localHostname,
            'port': port,
          }),
        ),
        datagram.address,
        datagram.port,
      );
    });
  }

  Future<void> _handlePairRequest(HttpRequest request) async {
    final body = await _readJsonBody(request);
    final clientId = body['clientId'] as String? ?? '';
    final clientName = body['clientName'] as String? ?? clientId;
    final code = body['code'] as String? ?? '';
    final secret = body['secret'] as String? ?? '';
    if (!RegExp(r'^[A-Za-z0-9_-]{1,64}$').hasMatch(clientId) ||
        !RegExp(r'^\d{4}$').hasMatch(code) ||
        secret.length < 24) {
      await _sendJson(
        request.response,
        HttpStatus.badRequest,
        {'ok': false, 'error': '配对参数无效'},
      );
      return;
    }
    final accepted = await pairingPrompt?.call(clientName, code) ?? false;
    if (!accepted) {
      await _sendJson(
        request.response,
        HttpStatus.forbidden,
        {'ok': false, 'error': '开发板未确认配对'},
      );
      return;
    }
    _pairedClients[clientId] = secret;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'remote_paired_clients',
      jsonEncode(_pairedClients),
    );
    await _sendJson(request.response, HttpStatus.ok, {
      'ok': true,
      'deviceId': _deviceId,
      'name': Platform.localHostname,
    });
  }

  String _randomSecret(int byteCount) {
    return base64UrlEncode(
      List<int>.generate(byteCount, (_) => Random.secure().nextInt(256)),
    ).replaceAll('=', '');
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

  Future<void> _sendWeatherConfiguration(HttpResponse response) async {
    final weather = WeatherService.instance;
    await _sendJson(
      response,
      HttpStatus.ok,
      {
        'ok': true,
        'autoLocation': weather.autoLocation,
        'location': weather.manualLocation,
        'hasApiKey': weather.hasApiKey,
      },
    );
  }

  Future<void> _handleWeatherConfiguration(HttpRequest request) async {
    if (request.contentLength > 64 * 1024) {
      await _sendJson(
        request.response,
        HttpStatus.requestEntityTooLarge,
        {'ok': false, 'error': '配置数据过大'},
      );
      return;
    }
    final body = await utf8.decoder.bind(request).join();
    final value = jsonDecode(body);
    if (value is! Map<String, dynamic>) {
      await _sendJson(
        request.response,
        HttpStatus.badRequest,
        {'ok': false, 'error': '配置格式不正确'},
      );
      return;
    }
    final autoLocation = value['autoLocation'] as bool? ?? true;
    final location = value['location'] as String? ?? '';
    final apiKey = value['apiKey'] as String?;
    if (!autoLocation && location.trim().isEmpty) {
      await _sendJson(
        request.response,
        HttpStatus.badRequest,
        {'ok': false, 'error': '手动定位时必须填写城市或地区'},
      );
      return;
    }
    await WeatherService.instance.updateConfiguration(
      autoLocation: autoLocation,
      location: location,
      apiKey: apiKey,
    );
    await _sendJson(
      request.response,
      HttpStatus.ok,
      {
        'ok': true,
        'message': WeatherService.instance.error ?? '天气配置已更新',
        'weatherAvailable': WeatherService.instance.weather != null,
      },
    );
  }

  Future<void> _sendHaConfiguration(HttpResponse response) async {
    final homeAssistant = HomeAssistantService.instance;
    await _sendJson(response, HttpStatus.ok, {
      'ok': true,
      'url': homeAssistant.url,
      'configured': homeAssistant.configured,
      'connected': homeAssistant.connected,
    });
  }

  Future<void> _handleHaConfiguration(HttpRequest request) async {
    final value = await _readJsonBody(request);
    final url = value['url'] as String? ?? HomeAssistantService.defaultUrl;
    final token = value['token'] as String? ?? '';
    try {
      await HomeAssistantService.instance.saveConfiguration(
        url: url,
        token: token,
      );
      await _sendJson(request.response, HttpStatus.ok, {
        'ok': true,
        'message': HomeAssistantService.instance.connected
            ? 'Home Assistant 已连接'
            : '配置已保存，正在连接 Home Assistant',
      });
    } catch (error) {
      await _sendJson(request.response, HttpStatus.badRequest, {
        'ok': false,
        'error': '$error',
      });
    }
  }

  Future<Map<String, dynamic>> _readJsonBody(HttpRequest request) async {
    if (request.contentLength > 64 * 1024) {
      throw const FormatException('请求数据过大');
    }
    final value = jsonDecode(await utf8.decoder.bind(request).join());
    if (value is! Map<String, dynamic>) {
      throw const FormatException('请求格式不正确');
    }
    return value;
  }

  Future<void> _sendSerialStatus(HttpRequest request) async {
    final serial = SerialPortService.instance;
    final since = int.tryParse(request.uri.queryParameters['since'] ?? '') ?? 0;
    final devices = await serial.scanDevices();
    await _sendJson(
      request.response,
      HttpStatus.ok,
      {
        'ok': true,
        'open': serial.open,
        'opening': serial.opening,
        'device': serial.device ?? '',
        'baudRate': serial.baudRate,
        'parity': serial.parity.name,
        'devices': devices,
        'output': serial.outputAfter(since),
        'outputStart': serial.outputStartOffset,
        'outputEnd': serial.outputEndOffset,
        'reset': since < serial.outputStartOffset,
      },
    );
  }

  Future<void> _handleSerialOpen(HttpRequest request) async {
    final value = await _readJsonBody(request);
    final device = (value['device'] as String? ?? '').trim();
    final baudRate = value['baudRate'] as int? ?? 115200;
    final parityName = value['parity'] as String? ?? 'none';
    final parity = SerialParity.values.firstWhere(
      (item) => item.name == parityName,
      orElse: () => SerialParity.none,
    );
    if (!RegExp(r'^/dev/tty[A-Za-z0-9._-]+$').hasMatch(device)) {
      await _sendJson(
        request.response,
        HttpStatus.badRequest,
        {'ok': false, 'error': '串口设备路径无效'},
      );
      return;
    }
    await SerialPortService.instance.openPort(
      device: device,
      baudRate: baudRate,
      parity: parity,
    );
    await _sendJson(
      request.response,
      HttpStatus.ok,
      {
        'ok': SerialPortService.instance.open,
        'error': SerialPortService.instance.open ? '' : '串口打开失败，请查看终端输出',
      },
    );
  }

  Future<void> _handleSerialSend(HttpRequest request) async {
    final value = await _readJsonBody(request);
    final data = value['data'] as String? ?? '';
    if (data.length > 16 * 1024) {
      await _sendJson(
        request.response,
        HttpStatus.badRequest,
        {'ok': false, 'error': '单次发送不能超过 16 KB'},
      );
      return;
    }
    await SerialPortService.instance.send(data);
    await _sendJson(
      request.response,
      HttpStatus.ok,
      {'ok': true},
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
    Map<String, Object?> body,
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
  <title>设备远程设置</title>
  <style>
    :root { color-scheme: light dark; font-family: system-ui, sans-serif; }
    body { margin: 0; min-height: 100vh; display: grid; place-items: center;
      background: #f4f6f8; color: #1b1b1f; }
    main { width: min(88vw, 560px); padding: 28px; margin: 24px 0;
      border-radius: 24px;
      background: white; box-shadow: 0 12px 40px #0002; }
    h1 { margin: 0 0 8px; font-size: 24px; }
    p { color: #5f6368; }
    .drop { display: grid; place-items: center; min-height: 220px;
      border: 2px dashed #9aa0a6; border-radius: 18px; overflow: hidden; }
    img { display: none; width: 100%; max-height: 320px; object-fit: contain; }
    input { max-width: 90%; }
    input[type=text], input[type=password] { box-sizing: border-box; width: 100%;
      max-width: none; padding: 12px; margin-top: 6px; border: 1px solid #9aa0a6;
      border-radius: 12px; font-size: 16px; background: transparent; color: inherit; }
    label.field { display: block; margin-top: 14px; }
    label.check { display: flex; align-items: center; gap: 8px; margin-top: 16px; }
    hr { border: 0; border-top: 1px solid #9aa0a655; margin: 32px 0; }
    button { width: 100%; margin-top: 18px; padding: 14px; border: 0;
      border-radius: 999px; font-size: 16px; background: #1967d2; color: white; }
    button:disabled { opacity: .5; }
    .row { display: flex; gap: 10px; align-items: center; }
    .row > * { min-width: 0; flex: 1; }
    select { width: 100%; padding: 11px; border-radius: 10px;
      border: 1px solid #9aa0a6; background: transparent; color: inherit; }
    #terminal { box-sizing: border-box; width: 100%; height: 280px;
      overflow: auto; white-space: pre; padding: 12px; border-radius: 12px;
      background: #111318; color: #d6e1e8; font: 13px monospace; }
    .compact { width: auto; margin-top: 0; padding: 11px 18px; }
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
  <hr>
  <h1>天气设置</h1>
  <p>使用 OpenWeather 当前天气服务。API Key 不会在网页中回显。</p>
  <label class="check">
    <input id="autoLocation" type="checkbox"> 根据公网 IP 自动定位
  </label>
  <label class="field">城市或地区
    <input id="locationInput" type="text" placeholder="例如：深圳 或 Shenzhen,CN">
  </label>
  <label class="field">OpenWeather API Key
    <input id="apiKey" type="password" autocomplete="off" placeholder="输入新的 API Key">
  </label>
  <button id="saveWeather">保存并刷新天气</button>
  <div id="weatherStatus"></div>
  <hr>
  <h1>Home Assistant 设置</h1>
  <p>长期访问令牌不会在网页中回显。留空表示保留当前令牌。</p>
  <label class="field">Home Assistant 地址
    <input id="haUrl" type="text" placeholder="http://127.0.0.1:8123">
  </label>
  <label class="field">长期访问令牌
    <input id="haToken" type="password" autocomplete="off" placeholder="输入长期访问令牌">
  </label>
  <button id="saveHa">保存并连接</button>
  <div id="haStatus"></div>
  <hr>
  <h1>串口终端</h1>
  <p>页面关闭后串口仍保持打开，直至手动关闭。</p>
  <div class="row">
    <select id="serialDevice"></select>
    <select id="serialBaud">
      <option>9600</option><option>19200</option><option>38400</option>
      <option>57600</option><option selected>115200</option>
      <option>230400</option><option>460800</option><option>921600</option>
    </select>
    <select id="serialParity">
      <option value="none">无校验</option>
      <option value="odd">奇校验</option>
      <option value="even">偶校验</option>
    </select>
  </div>
  <div class="row">
    <button id="serialOpen">打开串口</button>
    <button id="serialClose">关闭串口</button>
  </div>
  <div id="serialStatus"></div>
  <pre id="terminal"></pre>
  <div class="row">
    <input id="serialInput" type="text" placeholder="输入要发送的数据">
    <label class="check"><input id="serialNewline" type="checkbox" checked>追加换行</label>
    <button id="serialSend" class="compact">发送</button>
  </div>
</main>
<script>
const file = document.querySelector('#file');
const preview = document.querySelector('#preview');
const hint = document.querySelector('#hint');
const upload = document.querySelector('#upload');
const status = document.querySelector('#status');
const autoLocation = document.querySelector('#autoLocation');
const locationInput = document.querySelector('#locationInput');
const apiKey = document.querySelector('#apiKey');
const saveWeather = document.querySelector('#saveWeather');
const weatherStatus = document.querySelector('#weatherStatus');
const haUrl = document.querySelector('#haUrl');
const haToken = document.querySelector('#haToken');
const saveHa = document.querySelector('#saveHa');
const haStatus = document.querySelector('#haStatus');
const serialDevice = document.querySelector('#serialDevice');
const serialBaud = document.querySelector('#serialBaud');
const serialParity = document.querySelector('#serialParity');
const serialOpen = document.querySelector('#serialOpen');
const serialClose = document.querySelector('#serialClose');
const serialStatus = document.querySelector('#serialStatus');
const terminal = document.querySelector('#terminal');
const serialInput = document.querySelector('#serialInput');
const serialNewline = document.querySelector('#serialNewline');
const serialSend = document.querySelector('#serialSend');
let serialOffset = 0;
let serialPolling = false;
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
autoLocation.onchange = () => {
  locationInput.disabled = autoLocation.checked;
};
async function loadWeatherConfig() {
  try {
    const response = await fetch('/api/weather-config' + location.search);
    const config = await response.json();
    autoLocation.checked = config.autoLocation;
    locationInput.value = config.location || '';
    locationInput.disabled = autoLocation.checked;
    apiKey.placeholder = config.hasApiKey
      ? '已配置；留空表示不修改'
      : '请输入 OpenWeather API Key';
  } catch (error) {
    weatherStatus.textContent = '读取天气配置失败：' + error.message;
  }
}
saveWeather.onclick = async () => {
  saveWeather.disabled = true;
  weatherStatus.textContent = '正在保存并获取天气…';
  try {
    const response = await fetch('/api/weather-config' + location.search, {
      method: 'POST',
      headers: {'Content-Type': 'application/json'},
      body: JSON.stringify({
        autoLocation: autoLocation.checked,
        location: locationInput.value,
        apiKey: apiKey.value
      })
    });
    const result = await response.json();
    if (!response.ok || !result.ok) throw new Error(result.error || '保存失败');
    apiKey.value = '';
    apiKey.placeholder = '已配置；留空表示不修改';
    weatherStatus.textContent = result.message;
  } catch (error) {
    weatherStatus.textContent = error.message;
  } finally {
    saveWeather.disabled = false;
  }
};
loadWeatherConfig();
async function loadHaConfig() {
  try {
    const response = await fetch('/api/ha-config' + location.search);
    const config = await response.json();
    haUrl.value = config.url || 'http://127.0.0.1:8123';
    haToken.placeholder = config.configured
      ? '已配置；留空表示不修改'
      : '请输入长期访问令牌';
    haStatus.textContent = config.connected ? 'Home Assistant 已连接' : '';
  } catch (error) {
    haStatus.textContent = '读取 Home Assistant 配置失败：' + error.message;
  }
}
saveHa.onclick = async () => {
  saveHa.disabled = true;
  haStatus.textContent = '正在安全保存并连接…';
  try {
    const response = await fetch('/api/ha-config' + location.search, {
      method: 'POST',
      headers: {'Content-Type': 'application/json'},
      body: JSON.stringify({url: haUrl.value, token: haToken.value})
    });
    const result = await response.json();
    if (!response.ok || !result.ok) throw new Error(result.error || '保存失败');
    haToken.value = '';
    haToken.placeholder = '已配置；留空表示不修改';
    haStatus.textContent = result.message;
  } catch (error) {
    haStatus.textContent = error.message;
  } finally {
    saveHa.disabled = false;
  }
};
loadHaConfig();
async function serialRequest(path, options) {
  const tokenQuery = location.search.replace(/^\?/, '');
  const response = await fetch(
    path + (path.includes('?') ? '&' : '?') + tokenQuery,
    options
  );
  const result = await response.json();
  if (!response.ok || !result.ok) throw new Error(result.error || '操作失败');
  return result;
}
async function pollSerial() {
  if (serialPolling) return;
  serialPolling = true;
  try {
    const result = await serialRequest(
      '/api/serial?since=' + serialOffset
    );
    const atBottom = terminal.scrollTop + terminal.clientHeight >=
      terminal.scrollHeight - 24;
    if (result.reset) terminal.textContent = result.output;
    else terminal.textContent += result.output;
    serialOffset = result.outputEnd;
    if (terminal.textContent.length > 131072) {
      terminal.textContent = terminal.textContent.slice(-131072);
    }
    if (atBottom) terminal.scrollTop = terminal.scrollHeight;
    const selected = serialDevice.value;
    serialDevice.innerHTML = '';
    result.devices.forEach(device => {
      const option = document.createElement('option');
      option.value = device; option.textContent = device;
      serialDevice.appendChild(option);
    });
    if (result.device && !result.devices.includes(result.device)) {
      const option = document.createElement('option');
      option.value = result.device; option.textContent = result.device;
      serialDevice.appendChild(option);
    }
    if (result.open && result.device) serialDevice.value = result.device;
    if (result.open) {
      serialBaud.value = String(result.baudRate);
      serialParity.value = result.parity;
    } else if (selected) serialDevice.value = selected;
    const busy = result.open || result.opening;
    serialDevice.disabled = busy;
    serialBaud.disabled = busy;
    serialParity.disabled = busy;
    serialOpen.disabled = busy || !serialDevice.value;
    serialClose.disabled = !busy;
    serialSend.disabled = !result.open;
    serialInput.disabled = !result.open;
    serialStatus.textContent = result.open
      ? '已打开 ' + result.device
      : result.opening ? '正在打开…' : '未打开';
  } catch (error) {
    serialStatus.textContent = '串口状态读取失败：' + error.message;
  } finally {
    serialPolling = false;
  }
}
serialOpen.onclick = async () => {
  serialOpen.disabled = true;
  try {
    await serialRequest('/api/serial/open', {
      method: 'POST', headers: {'Content-Type': 'application/json'},
      body: JSON.stringify({
        device: serialDevice.value,
        baudRate: Number(serialBaud.value),
        parity: serialParity.value
      })
    });
  } catch (error) { serialStatus.textContent = error.message; }
  pollSerial();
};
serialClose.onclick = async () => {
  try {
    await serialRequest('/api/serial/close', {method: 'POST'});
  } catch (error) { serialStatus.textContent = error.message; }
  pollSerial();
};
async function sendSerial() {
  if (!serialInput.value) return;
  const data = serialInput.value + (serialNewline.checked ? '\n' : '');
  try {
    await serialRequest('/api/serial/send', {
      method: 'POST', headers: {'Content-Type': 'application/json'},
      body: JSON.stringify({data})
    });
    serialInput.value = '';
  } catch (error) { serialStatus.textContent = error.message; }
}
serialSend.onclick = sendSerial;
serialInput.onkeydown = event => {
  if (event.key === 'Enter') { event.preventDefault(); sendSerial(); }
};
pollSerial();
setInterval(pollSerial, 300);
</script>
</body>
</html>
''';
}

class RemoteNetworkAddress {
  const RemoteNetworkAddress({required this.name, required this.address});

  final String name;
  final InternetAddress address;

  String get label => '$name · ${address.address}';
}
