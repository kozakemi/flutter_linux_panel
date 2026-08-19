class HaArea {
  const HaArea({required this.id, required this.name});

  final String id;
  final String name;

  factory HaArea.fromJson(Map<String, dynamic> json) => HaArea(
        id: json['area_id'] as String? ?? json['id'] as String? ?? '',
        name: json['name'] as String? ?? '未命名房间',
      );
}

class HaDevice {
  const HaDevice({
    required this.id,
    required this.name,
    this.areaId,
  });

  final String id;
  final String name;
  final String? areaId;

  factory HaDevice.fromJson(Map<String, dynamic> json) => HaDevice(
        id: json['id'] as String? ?? '',
        name: json['name_by_user'] as String? ??
            json['name'] as String? ??
            '未命名设备',
        areaId: json['area_id'] as String?,
      );
}

class HaEntity {
  const HaEntity({
    required this.id,
    required this.name,
    this.deviceId,
    this.areaId,
    this.platform = '',
    this.disabled = false,
    this.hidden = false,
    this.category,
  });

  final String id;
  final String name;
  final String? deviceId;
  final String? areaId;
  final String platform;
  final bool disabled;
  final bool hidden;
  final String? category;

  String get domain => id.split('.').firstOrNull ?? '';

  factory HaEntity.fromJson(Map<String, dynamic> json) => HaEntity(
        id: json['entity_id'] as String? ?? '',
        name: json['name'] as String? ?? json['original_name'] as String? ?? '',
        deviceId: json['device_id'] as String?,
        areaId: json['area_id'] as String?,
        platform: json['platform'] as String? ?? '',
        disabled: json['disabled_by'] != null,
        hidden: json['hidden_by'] != null,
        category: json['entity_category'] as String?,
      );
}

class HaState {
  const HaState({
    required this.entityId,
    required this.state,
    required this.attributes,
    this.lastChanged,
  });

  final String entityId;
  final String state;
  final Map<String, dynamic> attributes;
  final DateTime? lastChanged;

  String get friendlyName => attributes['friendly_name'] as String? ?? '';
  String get deviceClass => attributes['device_class'] as String? ?? '';
  String get unit => attributes['unit_of_measurement'] as String? ?? '';
  bool get unavailable => state == 'unavailable' || state == 'unknown';
  bool get active => state == 'on' || state == 'open' || state == 'locked';

  factory HaState.fromJson(Map<String, dynamic> json) => HaState(
        entityId: json['entity_id'] as String? ?? '',
        state: '${json['state'] ?? 'unknown'}',
        attributes: Map<String, dynamic>.from(
          json['attributes'] as Map? ?? const <String, dynamic>{},
        ),
        lastChanged: DateTime.tryParse(json['last_changed'] as String? ?? ''),
      );

  HaState copyWith({String? state, Map<String, dynamic>? attributes}) =>
      HaState(
        entityId: entityId,
        state: state ?? this.state,
        attributes: attributes ?? this.attributes,
        lastChanged: lastChanged,
      );
}

class HaEntityView {
  const HaEntityView({
    required this.entity,
    required this.state,
    required this.areaId,
    required this.areaName,
    required this.deviceName,
    required this.favorite,
  });

  final HaEntity entity;
  final HaState state;
  final String? areaId;
  final String areaName;
  final String deviceName;
  final bool favorite;

  String get id => entity.id;
  String get domain => entity.domain;
  String get name => entity.name.isNotEmpty
      ? entity.name
      : state.friendlyName.isNotEmpty
          ? state.friendlyName
          : id;
  bool get available => !state.unavailable;
  bool get active => state.active;
  bool get controllable => domain == 'light' || domain == 'switch';
}
