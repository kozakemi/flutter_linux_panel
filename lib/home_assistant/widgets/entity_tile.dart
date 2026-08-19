import 'dart:async';

import 'package:flutter/material.dart';

import '../home_assistant_service.dart';
import '../models/ha_models.dart';

class HaEntityTile extends StatelessWidget {
  const HaEntityTile({
    super.key,
    required this.entity,
    required this.service,
  });

  final HaEntityView entity;
  final HomeAssistantService service;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final enabled = entity.available && service.connected;
    return Opacity(
      opacity: entity.available ? 1 : 0.48,
      child: Card(
        clipBehavior: Clip.antiAlias,
        color: entity.active && entity.controllable
            ? colors.primaryContainer
            : colors.surfaceContainer,
        child: InkWell(
          onTap: enabled && entity.controllable
              ? () => unawaited(_toggle(context))
              : null,
          onLongPress: () => _showDetails(context),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 8, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      _icon,
                      size: 30,
                      color: entity.active && entity.controllable
                          ? colors.onPrimaryContainer
                          : colors.onSurfaceVariant,
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: entity.favorite ? '取消收藏' : '收藏',
                      visualDensity: VisualDensity.compact,
                      onPressed: () => service.toggleFavorite(entity.id),
                      icon: Icon(
                        entity.favorite ? Icons.star : Icons.star_border,
                        size: 21,
                        color: entity.favorite ? colors.tertiary : null,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                Text(
                  entity.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 3),
                Text(
                  _stateText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                ),
                if (entity.domain == 'light' && entity.active) ...[
                  const SizedBox(height: 7),
                  LinearProgressIndicator(
                    value: _brightness / 100,
                    minHeight: 4,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _toggle(BuildContext context) async {
    final success = await service.toggle(entity);
    if (!success && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(service.error ?? '设备控制失败')),
      );
    }
  }

  Future<void> _showDetails(BuildContext context) async {
    var brightness = _brightness;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(_icon, size: 30),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            entity.name,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          Text('${entity.areaName} · ${entity.id}'),
                        ],
                      ),
                    ),
                    if (entity.controllable)
                      Switch(
                        value: entity.active,
                        onChanged: entity.available && service.connected
                            ? (_) {
                                unawaited(service.toggle(entity));
                                Navigator.pop(sheetContext);
                              }
                            : null,
                      ),
                  ],
                ),
                if (entity.domain == 'light') ...[
                  const SizedBox(height: 18),
                  Text('亮度 ${brightness.round()}%'),
                  Slider(
                    value: brightness,
                    min: 1,
                    max: 100,
                    onChanged: entity.available && service.connected
                        ? (value) => setState(() => brightness = value)
                        : null,
                    onChangeEnd: (value) {
                      unawaited(service.setLightBrightness(entity, value));
                    },
                  ),
                ],
                const SizedBox(height: 8),
                _detail('状态', _stateText),
                if (entity.deviceName.isNotEmpty)
                  _detail('设备', entity.deviceName),
                if (entity.state.lastChanged != null)
                  _detail(
                      '最后变化', entity.state.lastChanged!.toLocal().toString()),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _detail(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            SizedBox(width: 88, child: Text(label)),
            Expanded(child: SelectableText(value)),
          ],
        ),
      );

  double get _brightness {
    final raw = entity.state.attributes['brightness'];
    if (raw is num) return (raw.toDouble() / 2.55).clamp(1, 100);
    return entity.active ? 100 : 1;
  }

  IconData get _icon => switch (entity.domain) {
        'light' => entity.active ? Icons.lightbulb : Icons.lightbulb_outline,
        'switch' => Icons.power_settings_new,
        'binary_sensor' => switch (entity.state.deviceClass) {
            'motion' || 'occupancy' || 'presence' => Icons.sensors,
            _ => entity.active ? Icons.door_front_door : Icons.door_back_door,
          },
        'sensor' => switch (entity.state.deviceClass) {
            'temperature' => Icons.thermostat,
            'humidity' => Icons.water_drop_outlined,
            'power' || 'energy' => Icons.bolt,
            _ => Icons.sensors,
          },
        _ => Icons.device_unknown,
      };

  String get _stateText {
    if (!entity.available) return '不可用';
    if (entity.domain == 'sensor') {
      return '${entity.state.state}${entity.state.unit.isEmpty ? '' : ' ${entity.state.unit}'}';
    }
    if (entity.domain == 'binary_sensor') {
      final active = entity.active;
      return switch (entity.state.deviceClass) {
        'motion' => active ? '检测到运动' : '无运动',
        'occupancy' || 'presence' => active ? '有人' : '无人',
        _ => active ? '已打开' : '已关闭',
      };
    }
    return entity.active ? '已开启' : '已关闭';
  }
}
