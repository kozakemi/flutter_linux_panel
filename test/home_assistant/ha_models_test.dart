import 'package:flutter_test/flutter_test.dart';

import 'package:demo1/home_assistant/models/ha_models.dart';

void main() {
  test('parses registry relations and state attributes', () {
    final entity = HaEntity.fromJson(<String, dynamic>{
      'entity_id': 'sensor.living_temperature',
      'device_id': 'device-1',
      'area_id': 'living-room',
      'original_name': 'Temperature',
      'platform': 'matter',
    });
    final state = HaState.fromJson(<String, dynamic>{
      'entity_id': entity.id,
      'state': '23.5',
      'attributes': <String, dynamic>{
        'device_class': 'temperature',
        'unit_of_measurement': '°C',
      },
    });

    expect(entity.domain, 'sensor');
    expect(entity.areaId, 'living-room');
    expect(entity.platform, 'matter');
    expect(state.deviceClass, 'temperature');
    expect(state.unit, '°C');
    expect(state.unavailable, isFalse);
  });

  test('marks unavailable states and hidden registry entries', () {
    final entity = HaEntity.fromJson(<String, dynamic>{
      'entity_id': 'switch.hidden',
      'hidden_by': 'user',
      'disabled_by': 'integration',
    });
    final state = HaState.fromJson(<String, dynamic>{
      'entity_id': entity.id,
      'state': 'unavailable',
      'attributes': <String, dynamic>{},
    });

    expect(entity.hidden, isTrue);
    expect(entity.disabled, isTrue);
    expect(state.unavailable, isTrue);
  });
}
