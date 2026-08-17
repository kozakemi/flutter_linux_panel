import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

class RemoteLaunchpadAction {
  const RemoteLaunchpadAction({
    required this.clientId,
    required this.clientName,
    required this.id,
    required this.name,
    required this.iconPath,
    required this.order,
    required this.online,
    this.kind = 'action',
  });

  final String clientId;
  final String clientName;
  final String id;
  final String name;
  final String iconPath;
  final int order;
  final bool online;
  final String kind;

  String get key => '$clientId:$id';

  RemoteLaunchpadAction copyWith({bool? online}) => RemoteLaunchpadAction(
        clientId: clientId,
        clientName: clientName,
        id: id,
        name: name,
        iconPath: iconPath,
        order: order,
        online: online ?? this.online,
        kind: kind,
      );
}

class RemoteMediaState {
  const RemoteMediaState({
    this.available = false,
    this.playing = false,
    this.title = '',
    this.artist = '',
    this.album = '',
    this.artworkBase64 = '',
    this.lyrics = '',
    this.message = '',
    this.position = 0,
    this.duration = 0,
    this.volume = 0,
    this.muted = false,
  });

  final bool available;
  final bool playing;
  final String title;
  final String artist;
  final String album;
  final String artworkBase64;
  final String lyrics;
  final String message;
  final double position;
  final double duration;
  final double volume;
  final bool muted;

  factory RemoteMediaState.fromJson(
    Map<String, dynamic> json, [
    RemoteMediaState? previous,
  ]) {
    return RemoteMediaState(
      available: json['available'] as bool? ?? false,
      playing: json['playing'] as bool? ?? false,
      title: json['title'] as String? ?? '',
      artist: json['artist'] as String? ?? '',
      album: json['album'] as String? ?? '',
      artworkBase64:
          json['artworkBase64'] as String? ?? previous?.artworkBase64 ?? '',
      lyrics: json['lyrics'] as String? ?? '',
      message: json['message'] as String? ?? '',
      position: (json['position'] as num?)?.toDouble() ?? 0,
      duration: (json['duration'] as num?)?.toDouble() ?? 0,
      volume: (json['volume'] as num?)?.toDouble() ?? 0,
      muted: json['muted'] as bool? ?? false,
    );
  }
}

class RemotePerformanceState {
  const RemotePerformanceState({
    this.available = false,
    this.cpu = 0,
    this.cpuName = '',
    this.cores = const [],
    this.load = const [],
    this.temperature = 0,
    this.memoryTotal = 0,
    this.memoryUsed = 0,
    this.diskTotal = 0,
    this.diskUsed = 0,
    this.networkDown = 0,
    this.networkUp = 0,
    this.uptime = 0,
    this.message = '',
    this.gpuAvailable = false,
    this.gpuName = '',
    this.gpu = 0,
    this.gpuMemoryUsed = 0,
    this.gpuMemoryTotal = 0,
    this.gpuMemoryShared = false,
    this.gpuTemperature = 0,
    this.gpuPower = 0,
    this.gpuFrequency = 0,
    this.gpuFrequencyMax = 0,
    this.gpuMessage = '',
  });

  final bool available;
  final double cpu;
  final String cpuName;
  final List<double> cores;
  final List<double> load;
  final double temperature;
  final int memoryTotal;
  final int memoryUsed;
  final int diskTotal;
  final int diskUsed;
  final double networkDown;
  final double networkUp;
  final double uptime;
  final String message;
  final bool gpuAvailable;
  final String gpuName;
  final double gpu;
  final int gpuMemoryUsed;
  final int gpuMemoryTotal;
  final bool gpuMemoryShared;
  final double gpuTemperature;
  final double gpuPower;
  final double gpuFrequency;
  final double gpuFrequencyMax;
  final String gpuMessage;

  factory RemotePerformanceState.fromJson(Map<String, dynamic> json) {
    List<double> values(String key) => (json[key] as List? ?? const [])
        .whereType<num>()
        .map((value) => value.toDouble())
        .toList();
    return RemotePerformanceState(
      available: json['available'] as bool? ?? false,
      cpu: (json['cpu'] as num?)?.toDouble() ?? 0,
      cpuName: json['cpuName'] as String? ?? '',
      cores: values('cores'),
      load: values('load'),
      temperature: (json['temperature'] as num?)?.toDouble() ?? 0,
      memoryTotal: json['memoryTotal'] as int? ?? 0,
      memoryUsed: json['memoryUsed'] as int? ?? 0,
      diskTotal: json['diskTotal'] as int? ?? 0,
      diskUsed: json['diskUsed'] as int? ?? 0,
      networkDown: (json['networkDown'] as num?)?.toDouble() ?? 0,
      networkUp: (json['networkUp'] as num?)?.toDouble() ?? 0,
      uptime: (json['uptime'] as num?)?.toDouble() ?? 0,
      message: json['message'] as String? ?? '',
      gpuAvailable: json['gpuAvailable'] as bool? ?? false,
      gpuName: json['gpuName'] as String? ?? '',
      gpu: (json['gpu'] as num?)?.toDouble() ?? 0,
      gpuMemoryUsed: json['gpuMemoryUsed'] as int? ?? 0,
      gpuMemoryTotal: json['gpuMemoryTotal'] as int? ?? 0,
      gpuMemoryShared: json['gpuMemoryShared'] as bool? ?? false,
      gpuTemperature: (json['gpuTemperature'] as num?)?.toDouble() ?? 0,
      gpuPower: (json['gpuPower'] as num?)?.toDouble() ?? 0,
      gpuFrequency: (json['gpuFrequency'] as num?)?.toDouble() ?? 0,
      gpuFrequencyMax: (json['gpuFrequencyMax'] as num?)?.toDouble() ?? 0,
      gpuMessage: json['gpuMessage'] as String? ?? '',
    );
  }
}

class RemoteLaunchpadComputer {
  const RemoteLaunchpadComputer({
    required this.id,
    required this.name,
    required this.online,
    required this.actionCount,
  });

  final String id;
  final String name;
  final bool online;
  final int actionCount;
}

class RemoteLaunchpadService extends ChangeNotifier {
  RemoteLaunchpadService._();

  static final RemoteLaunchpadService instance = RemoteLaunchpadService._();
  static const int _maxIconBytes = 512 * 1024;

  final Map<String, WebSocket> _clients = <String, WebSocket>{};
  final Map<String, RemoteLaunchpadAction> _actions =
      <String, RemoteLaunchpadAction>{};
  final Map<String, RemoteMediaState> _mediaStates =
      <String, RemoteMediaState>{};
  final Map<String, RemotePerformanceState> _performanceStates =
      <String, RemotePerformanceState>{};
  int _requestSequence = 0;
  bool _initialized = false;

  List<RemoteLaunchpadAction> get actions {
    final result = _actions.values.toList()
      ..sort((a, b) {
        final client = a.clientName.compareTo(b.clientName);
        if (client != 0) return client;
        final order = a.order.compareTo(b.order);
        return order != 0 ? order : a.name.compareTo(b.name);
      });
    return List<RemoteLaunchpadAction>.unmodifiable(result);
  }

  List<RemoteLaunchpadComputer> get computers {
    final grouped = <String, List<RemoteLaunchpadAction>>{};
    for (final action in _actions.values) {
      grouped.putIfAbsent(action.clientId, () => []).add(action);
    }
    final result = [
      for (final entry in grouped.entries)
        RemoteLaunchpadComputer(
          id: entry.key,
          name: entry.value.first.clientName,
          online: entry.value.any((action) => action.online),
          actionCount: entry.value.length,
        ),
    ]..sort((a, b) => a.name.compareTo(b.name));
    return List<RemoteLaunchpadComputer>.unmodifiable(result);
  }

  List<RemoteLaunchpadAction> actionsForComputer(String clientId) {
    final result =
        _actions.values.where((action) => action.clientId == clientId).toList()
          ..sort((a, b) {
            final order = a.order.compareTo(b.order);
            return order != 0 ? order : a.name.compareTo(b.name);
          });
    return List<RemoteLaunchpadAction>.unmodifiable(result);
  }

  RemoteMediaState mediaStateForComputer(String clientId) =>
      _mediaStates[clientId] ?? const RemoteMediaState();

  RemotePerformanceState performanceStateForComputer(String clientId) =>
      _performanceStates[clientId] ?? const RemotePerformanceState();

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    try {
      final manifest = File('${_cacheDirectory.path}/actions.json');
      if (!await manifest.exists()) return;
      final value = jsonDecode(await manifest.readAsString());
      if (value is! List) return;
      for (final item in value.whereType<Map<String, dynamic>>()) {
        final action = RemoteLaunchpadAction(
          clientId: item['clientId'] as String? ?? '',
          clientName: item['clientName'] as String? ?? '',
          id: item['id'] as String? ?? '',
          name: item['name'] as String? ?? '',
          iconPath: item['iconPath'] as String? ?? '',
          order: item['order'] as int? ?? 0,
          online: false,
          kind: item['kind'] as String? ?? 'action',
        );
        if (action.clientId.isNotEmpty && action.id.isNotEmpty) {
          _actions[action.key] = action;
        }
      }
      notifyListeners();
    } catch (_) {
      // A damaged cache must not prevent the remote web service from starting.
    }
  }

  void accept(WebSocket socket) {
    String? sessionClientId;
    socket.listen(
      (message) async {
        if (message is! String) return;
        try {
          final value = jsonDecode(message);
          if (value is! Map<String, dynamic>) return;
          if (value['type'] == 'registerActions') {
            sessionClientId = await _register(socket, value);
          } else if (value['type'] == 'mediaState' &&
              sessionClientId != null &&
              value['state'] is Map<String, dynamic>) {
            _mediaStates[sessionClientId!] = RemoteMediaState.fromJson(
              value['state'] as Map<String, dynamic>,
              _mediaStates[sessionClientId],
            );
            notifyListeners();
          } else if (value['type'] == 'performanceState' &&
              sessionClientId != null &&
              value['state'] is Map<String, dynamic>) {
            _performanceStates[sessionClientId!] =
                RemotePerformanceState.fromJson(
              value['state'] as Map<String, dynamic>,
            );
            notifyListeners();
          }
        } catch (error) {
          _send(socket, {
            'type': 'error',
            'message': '消息处理失败：$error',
          });
        }
      },
      onDone: () => _disconnect(sessionClientId, socket),
      onError: (_) => _disconnect(sessionClientId, socket),
      cancelOnError: true,
    );
  }

  Future<String> _register(
    WebSocket socket,
    Map<String, dynamic> message,
  ) async {
    final clientId = _safeId(message['clientId'] as String? ?? '');
    final clientName = (message['clientName'] as String? ?? clientId).trim();
    final rawActions = message['actions'];
    if (clientId.isEmpty || rawActions is! List || rawActions.length > 64) {
      throw const FormatException('clientId 或 actions 无效');
    }

    final previous = _clients[clientId];
    if (previous != null && previous != socket) {
      unawaited(previous.close(WebSocketStatus.goingAway, '新的连接已建立'));
    }
    _clients[clientId] = socket;

    final registeredKeys = <String>{};
    for (var index = 0; index < rawActions.length; index++) {
      final rawAction = rawActions[index];
      if (rawAction is! Map<String, dynamic>) continue;
      final actionId = _safeId(rawAction['id'] as String? ?? '');
      final name = (rawAction['name'] as String? ?? '').trim();
      final iconBase64 = rawAction['iconBase64'] as String? ?? '';
      final iconFormat =
          (rawAction['iconFormat'] as String? ?? 'png').toLowerCase();
      if (actionId.isEmpty || name.isEmpty || name.length > 40) continue;
      final key = '$clientId:$actionId';
      final oldAction = _actions[key];
      final iconPath = iconBase64.isEmpty
          ? oldAction?.iconPath ?? ''
          : await _cacheIcon(clientId, actionId, iconFormat, iconBase64);
      _actions[key] = RemoteLaunchpadAction(
        clientId: clientId,
        clientName: clientName.isEmpty ? clientId : clientName,
        id: actionId,
        name: name,
        iconPath: iconPath,
        order: rawAction['order'] as int? ?? index,
        online: true,
        kind: switch (rawAction['kind'] as String?) {
          'media' => 'media',
          'performance' => 'performance',
          _ => 'action',
        },
      );
      registeredKeys.add(key);
    }

    for (final entry in _actions.entries.toList()) {
      if (entry.value.clientId == clientId &&
          !registeredKeys.contains(entry.key)) {
        _actions.remove(entry.key);
      }
    }
    await _persistActions();
    notifyListeners();
    _send(socket, {
      'type': 'registered',
      'clientId': clientId,
      'actionCount': registeredKeys.length,
    });
    return clientId;
  }

  Future<String> _cacheIcon(
    String clientId,
    String actionId,
    String format,
    String encoded,
  ) async {
    final extension = switch (format) {
      'jpg' || 'jpeg' => 'jpg',
      'webp' => 'webp',
      'svg' => 'svg',
      _ => 'png',
    };
    final Uint8List bytes;
    try {
      bytes = base64Decode(encoded);
    } catch (_) {
      throw const FormatException('图标不是有效的 Base64 数据');
    }
    if (bytes.isEmpty || bytes.length > _maxIconBytes) {
      throw const FormatException('图标必须小于 512 KB');
    }
    final directory = _cacheDirectory;
    await directory.create(recursive: true);
    final file = File('${directory.path}/${clientId}_$actionId.$extension');
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  bool invoke(RemoteLaunchpadAction action) {
    final socket = _clients[action.clientId];
    if (socket == null || socket.readyState != WebSocket.open) return false;
    _send(socket, {
      'type': 'invoke',
      'actionId': action.id,
      'requestId':
          '${DateTime.now().millisecondsSinceEpoch}-${++_requestSequence}',
    });
    return true;
  }

  bool sendMediaCommand(String clientId, String command, [double? value]) {
    final socket = _clients[clientId];
    if (socket == null || socket.readyState != WebSocket.open) return false;
    _send(socket, {
      'type': 'mediaCommand',
      'command': command,
      if (value != null) 'value': value,
    });
    return true;
  }

  Future<bool> removeComputer(String clientId) async {
    final safeClientId = _safeId(clientId);
    if (safeClientId.isEmpty) return false;
    final removedActions = _actions.values
        .where((action) => action.clientId == safeClientId)
        .toList();
    if (removedActions.isEmpty ||
        removedActions.any((action) => action.online) ||
        _clients.containsKey(safeClientId)) {
      return false;
    }

    _actions.removeWhere((_, action) => action.clientId == safeClientId);
    _mediaStates.remove(safeClientId);
    _performanceStates.remove(safeClientId);
    await _persistActions();
    for (final path
        in removedActions.map((action) => action.iconPath).toSet()) {
      if (path.isEmpty ||
          _actions.values.any((action) => action.iconPath == path)) {
        continue;
      }
      try {
        final file = File(path);
        if (await file.exists()) await file.delete();
      } catch (_) {}
    }
    notifyListeners();
    return true;
  }

  void _disconnect(String? clientId, WebSocket socket) {
    if (clientId == null || _clients[clientId] != socket) return;
    _clients.remove(clientId);
    _mediaStates.remove(clientId);
    _performanceStates.remove(clientId);
    for (final entry in _actions.entries.toList()) {
      if (entry.value.clientId == clientId) {
        _actions[entry.key] = entry.value.copyWith(online: false);
      }
    }
    notifyListeners();
  }

  void _send(WebSocket socket, Map<String, Object> value) {
    if (socket.readyState == WebSocket.open) socket.add(jsonEncode(value));
  }

  String _safeId(String value) =>
      RegExp(r'^[A-Za-z0-9_-]{1,64}$').hasMatch(value.trim())
          ? value.trim()
          : '';

  Directory get _cacheDirectory {
    final home = Platform.environment['HOME'] ?? Directory.current.path;
    return Directory('$home/.config/demo1/remote_launchpad_icons');
  }

  Future<void> _persistActions() async {
    final directory = _cacheDirectory;
    await directory.create(recursive: true);
    final data = [
      for (final action in _actions.values)
        {
          'clientId': action.clientId,
          'clientName': action.clientName,
          'id': action.id,
          'name': action.name,
          'iconPath': action.iconPath,
          'order': action.order,
          'kind': action.kind,
        },
    ];
    await File('${directory.path}/actions.json').writeAsString(
      jsonEncode(data),
      flush: true,
    );
  }
}
