import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api/ha_websocket_client.dart';
import 'models/ha_models.dart';

enum HaConnectionState {
  notConfigured,
  disconnected,
  connecting,
  synchronizing,
  connected,
  authenticationFailed,
}

class HomeAssistantService extends ChangeNotifier {
  HomeAssistantService._();

  static final HomeAssistantService instance = HomeAssistantService._();
  static const String defaultUrl = 'http://127.0.0.1:8123';
  static const String defaultConfigPath =
      '/etc/flutter-linux-panel/home-assistant.json';
  static const List<int> _retrySeconds = <int>[1, 2, 4, 8, 15, 30];
  static const String _favoritesKey = 'home_assistant_favorites';

  final HaWebSocketClient _client = HaWebSocketClient();
  final Map<String, HaArea> _areas = <String, HaArea>{};
  final Map<String, HaDevice> _devices = <String, HaDevice>{};
  final Map<String, HaEntity> _entities = <String, HaEntity>{};
  final Map<String, HaState> _states = <String, HaState>{};
  final Map<String, int> _optimisticRequests = <String, int>{};
  final Set<String> _favorites = <String>{};

  bool _initialized = false;
  String _url = defaultUrl;
  String _token = '';
  String _haVersion = '';
  String? _error;
  HaConnectionState _connectionState = HaConnectionState.notConfigured;
  Timer? _reconnectTimer;
  int _retryIndex = 0;
  int _generation = 0;
  int _optimisticSequence = 0;
  bool _manualDisconnect = false;

  String get configPath =>
      Platform.environment['FLUTTER_PANEL_HA_CONFIG'] ?? defaultConfigPath;
  String get url => _url;
  String get haVersion => _haVersion;
  String? get error => _error;
  bool get configured => _token.isNotEmpty;
  bool get connected => _connectionState == HaConnectionState.connected;
  HaConnectionState get connectionState => _connectionState;
  Set<String> get favorites => Set<String>.unmodifiable(_favorites);

  List<HaArea> get areas {
    final used =
        entityViews.map((entity) => entity.areaId).whereType<String>().toSet();
    final result = _areas.values
        .where((area) => used.contains(area.id))
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    return List<HaArea>.unmodifiable(result);
  }

  List<HaEntityView> get entityViews {
    final result = <HaEntityView>[];
    for (final state in _states.values) {
      final registry = _entities[state.entityId] ??
          HaEntity(
            id: state.entityId,
            name: state.friendlyName,
          );
      if (!_shouldDisplay(registry, state)) continue;
      final device =
          registry.deviceId == null ? null : _devices[registry.deviceId];
      final areaId = registry.areaId ?? device?.areaId;
      result.add(
        HaEntityView(
          entity: registry,
          state: state,
          areaId: areaId,
          areaName: areaId == null ? '未分配房间' : _areas[areaId]?.name ?? '未知房间',
          deviceName: device?.name ?? '',
          favorite: _favorites.contains(state.entityId),
        ),
      );
    }
    result.sort((a, b) {
      final area = a.areaName.compareTo(b.areaName);
      return area != 0 ? area : a.name.compareTo(b.name);
    });
    return List<HaEntityView>.unmodifiable(result);
  }

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    final prefs = await SharedPreferences.getInstance();
    _favorites.addAll(
      prefs.getStringList(_favoritesKey) ?? const <String>[],
    );
    await reloadConfiguration(connectAfterLoad: true);
  }

  Future<void> reloadConfiguration({bool connectAfterLoad = true}) async {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    try {
      final file = File(configPath);
      if (!await file.exists()) {
        _token = '';
        _url = defaultUrl;
        _connectionState = HaConnectionState.notConfigured;
        _error = '尚未配置 Home Assistant 访问令牌';
        notifyListeners();
        return;
      }
      final value = jsonDecode(await file.readAsString());
      if (value is! Map<String, dynamic>) {
        throw const FormatException('配置内容不是 JSON 对象');
      }
      _url = _normalizeUrl(value['url'] as String? ?? defaultUrl);
      _token = (value['token'] as String? ?? '').trim();
      if (_token.isEmpty) {
        _connectionState = HaConnectionState.notConfigured;
        _error = 'Home Assistant Token 为空';
        notifyListeners();
        return;
      }
      _error = null;
      _connectionState = HaConnectionState.disconnected;
      notifyListeners();
      if (connectAfterLoad) unawaited(connect());
    } catch (error) {
      _token = '';
      _connectionState = HaConnectionState.notConfigured;
      _error = '读取配置失败：$error';
      notifyListeners();
    }
  }

  Future<void> saveConfiguration({
    required String url,
    required String token,
  }) async {
    final normalizedUrl = _normalizeUrl(url);
    final nextToken = token.trim().isEmpty ? _token : token.trim();
    if (nextToken.isEmpty) throw const HaApiException('请输入长期访问令牌');
    final target = File(configPath);
    final temporary = File('$configPath.tmp');
    await target.parent.create(recursive: true);
    final directoryChmod =
        await Process.run('chmod', <String>['0700', target.parent.path]);
    if (directoryChmod.exitCode != 0) {
      throw HaApiException('设置配置目录权限失败：${directoryChmod.stderr}');
    }
    await temporary.writeAsString(
      const JsonEncoder.withIndent('  ').convert(<String, String>{
        'url': normalizedUrl,
        'token': nextToken,
      }),
      flush: true,
    );
    final chmod = await Process.run('chmod', <String>['0600', temporary.path]);
    if (chmod.exitCode != 0) {
      throw HaApiException('设置配置权限失败：${chmod.stderr}');
    }
    await temporary.rename(target.path);
    _url = normalizedUrl;
    _token = nextToken;
    _manualDisconnect = false;
    await connect(force: true);
  }

  Future<void> connect({bool force = false}) async {
    if (!configured) {
      _connectionState = HaConnectionState.notConfigured;
      notifyListeners();
      return;
    }
    if (!force &&
        (_connectionState == HaConnectionState.connecting ||
            _connectionState == HaConnectionState.synchronizing ||
            connected)) {
      return;
    }
    final generation = ++_generation;
    _manualDisconnect = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    await _client.close();
    _connectionState = HaConnectionState.connecting;
    _error = null;
    notifyListeners();
    _client.onEvent = _handleEvent;
    _client.onDisconnected = (error) {
      if (generation != _generation) return;
      _connectionState = HaConnectionState.disconnected;
      _error = error == null ? 'Home Assistant 连接已断开' : '$error';
      notifyListeners();
      _scheduleReconnect();
    };
    try {
      _haVersion = await _client.connect(_webSocketUri, _token);
      if (generation != _generation) return;
      _connectionState = HaConnectionState.synchronizing;
      notifyListeners();
      await _synchronize();
      if (generation != _generation) return;
      _connectionState = HaConnectionState.connected;
      _error = null;
      _retryIndex = 0;
      notifyListeners();
    } on HaApiException catch (error) {
      if (generation != _generation) return;
      final authentication = error.message.toLowerCase().contains('auth') ||
          error.message.contains('认证') ||
          error.message.toLowerCase().contains('token');
      _connectionState = authentication
          ? HaConnectionState.authenticationFailed
          : HaConnectionState.disconnected;
      _error = error.message;
      if (authentication) {
        _reconnectTimer?.cancel();
        _reconnectTimer = null;
      }
      notifyListeners();
      if (!authentication) _scheduleReconnect();
    } catch (error) {
      if (generation != _generation) return;
      _connectionState = HaConnectionState.disconnected;
      _error = '连接 Home Assistant 失败：$error';
      notifyListeners();
      _scheduleReconnect();
    }
  }

  Future<void> disconnect() async {
    _manualDisconnect = true;
    ++_generation;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    await _client.close();
    _connectionState = configured
        ? HaConnectionState.disconnected
        : HaConnectionState.notConfigured;
    notifyListeners();
  }

  Future<void> _synchronize() async {
    final statesResult = await _client.command(
      const <String, dynamic>{'type': 'get_states'},
    );
    final states = _mapList(statesResult, HaState.fromJson);

    final registries = await Future.wait<dynamic>(<Future<dynamic>>[
      _optionalCommand('config/area_registry/list'),
      _optionalCommand('config/device_registry/list'),
      _optionalCommand('config/entity_registry/list'),
    ]);
    final areas = _mapList(registries[0], HaArea.fromJson);
    final devices = _mapList(registries[1], HaDevice.fromJson);
    final entities = _mapList(registries[2], HaEntity.fromJson);

    _states
      ..clear()
      ..addEntries(states.map((state) => MapEntry(state.entityId, state)));
    _optimisticRequests.clear();
    _areas
      ..clear()
      ..addEntries(areas.map((area) => MapEntry(area.id, area)));
    _devices
      ..clear()
      ..addEntries(devices.map((device) => MapEntry(device.id, device)));
    _entities
      ..clear()
      ..addEntries(entities.map((entity) => MapEntry(entity.id, entity)));

    await _client.command(const <String, dynamic>{
      'type': 'subscribe_events',
      'event_type': 'state_changed',
    });
  }

  Future<dynamic> _optionalCommand(String type) async {
    try {
      return await _client.command(<String, dynamic>{'type': type});
    } catch (_) {
      return const <dynamic>[];
    }
  }

  List<T> _mapList<T>(dynamic value, T Function(Map<String, dynamic>) parse) {
    return (value as List? ?? const <dynamic>[])
        .whereType<Map>()
        .map((item) => parse(Map<String, dynamic>.from(item)))
        .where((item) {
      if (item is HaArea) return item.id.isNotEmpty;
      if (item is HaDevice) return item.id.isNotEmpty;
      if (item is HaEntity) return item.id.isNotEmpty;
      if (item is HaState) return item.entityId.isNotEmpty;
      return true;
    }).toList();
  }

  void _handleEvent(Map<String, dynamic> message) {
    final event = message['event'];
    if (event is! Map) return;
    final data = event['data'];
    if (data is! Map) return;
    final entityId = data['entity_id'] as String? ?? '';
    if (entityId.isEmpty) return;
    _optimisticRequests.remove(entityId);
    final next = data['new_state'];
    if (next == null) {
      _states.remove(entityId);
    } else if (next is Map) {
      _states[entityId] = HaState.fromJson(Map<String, dynamic>.from(next));
    }
    notifyListeners();
  }

  Future<bool> toggle(HaEntityView entity) async {
    if (!entity.available || !entity.controllable || !connected) return false;
    return _optimisticServiceCall(
      entity,
      service: entity.active ? 'turn_off' : 'turn_on',
      optimisticState: entity.active ? 'off' : 'on',
    );
  }

  Future<bool> setLightBrightness(HaEntityView entity, double percent) async {
    if (entity.domain != 'light' || !entity.available || !connected) {
      return false;
    }
    final brightness = (percent.clamp(0, 100) * 2.55).round();
    final attributes = Map<String, dynamic>.from(entity.state.attributes)
      ..['brightness'] = brightness;
    return _optimisticServiceCall(
      entity,
      service: 'turn_on',
      optimisticState: 'on',
      optimisticAttributes: attributes,
      serviceData: <String, dynamic>{'brightness_pct': percent.round()},
    );
  }

  Future<bool> _optimisticServiceCall(
    HaEntityView entity, {
    required String service,
    required String optimisticState,
    Map<String, dynamic>? optimisticAttributes,
    Map<String, dynamic>? serviceData,
  }) async {
    final previous = _states[entity.id];
    if (previous == null) return false;
    final requestId = ++_optimisticSequence;
    _optimisticRequests[entity.id] = requestId;
    _states[entity.id] = previous.copyWith(
      state: optimisticState,
      attributes: optimisticAttributes,
    );
    notifyListeners();
    try {
      await _client.command(<String, dynamic>{
        'type': 'call_service',
        'domain': entity.domain,
        'service': service,
        'target': <String, dynamic>{'entity_id': entity.id},
        if (serviceData != null) 'service_data': serviceData,
      });
      Timer(const Duration(seconds: 6), () {
        if (_optimisticRequests[entity.id] != requestId) return;
        _optimisticRequests.remove(entity.id);
        _states[entity.id] = previous;
        _error = '控制 ${entity.name} 后未收到状态确认';
        notifyListeners();
      });
      return true;
    } catch (error) {
      if (_optimisticRequests[entity.id] == requestId) {
        _optimisticRequests.remove(entity.id);
        _states[entity.id] = previous;
        _error = '控制 ${entity.name} 失败：$error';
        notifyListeners();
      }
      return false;
    }
  }

  Future<void> toggleFavorite(String entityId) async {
    if (!_favorites.add(entityId)) _favorites.remove(entityId);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_favoritesKey, _favorites.toList()..sort());
    notifyListeners();
  }

  bool _shouldDisplay(HaEntity entity, HaState state) {
    if (entity.disabled || entity.hidden || entity.category != null) {
      return false;
    }
    switch (entity.domain) {
      case 'light':
      case 'switch':
        return true;
      case 'binary_sensor':
        return const <String>{
          'door',
          'window',
          'opening',
          'garage_door',
          'motion',
          'occupancy',
          'presence',
        }.contains(state.deviceClass);
      case 'sensor':
        return const <String>{
          'temperature',
          'humidity',
          'power',
          'energy',
        }.contains(state.deviceClass);
      default:
        return false;
    }
  }

  void _scheduleReconnect() {
    if (_manualDisconnect || !configured || _reconnectTimer != null) return;
    final delay = _retrySeconds[_retryIndex.clamp(0, _retrySeconds.length - 1)];
    if (_retryIndex < _retrySeconds.length - 1) _retryIndex++;
    _reconnectTimer = Timer(Duration(seconds: delay), () {
      _reconnectTimer = null;
      unawaited(connect(force: true));
    });
  }

  Uri get _webSocketUri {
    final base = Uri.parse(_url);
    return base.replace(
      scheme: base.scheme == 'https' ? 'wss' : 'ws',
      path: '/api/websocket',
      query: null,
      fragment: null,
    );
  }

  String _normalizeUrl(String value) {
    var result = value.trim();
    if (result.isEmpty) result = defaultUrl;
    if (!result.contains('://')) result = 'http://$result';
    final uri = Uri.parse(result);
    if (!uri.hasScheme || uri.host.isEmpty) {
      throw const FormatException('Home Assistant 地址无效');
    }
    return uri
        .replace(path: '', query: null, fragment: null)
        .toString()
        .replaceFirst(
          RegExp(r'/$'),
          '',
        );
  }
}
