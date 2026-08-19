import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/display_service.dart';
import '../home_assistant_service.dart';
import '../models/ha_models.dart';
import '../widgets/entity_tile.dart';
import 'ha_settings_page.dart';

class HaDashboardPage extends StatefulWidget {
  const HaDashboardPage({super.key});

  @override
  State<HaDashboardPage> createState() => _HaDashboardPageState();
}

class _HaDashboardPageState extends State<HaDashboardPage> {
  static const String _all = '__all__';
  static const String _favorites = '__favorites__';
  static const String _unassigned = '__unassigned__';

  final HomeAssistantService _service = HomeAssistantService.instance;
  String _selection = _favorites;

  @override
  void initState() {
    super.initState();
    _service.addListener(_changed);
    if (!_service.connected && _service.configured) {
      unawaited(_service.connect());
    }
  }

  @override
  void dispose() {
    _service.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final scale = DisplayService.instance.scaleFactor;
    return Scaffold(
      appBar: AppBar(
        title: const Text('智能家居'),
        toolbarHeight: 56 * scale,
        actions: [
          _ConnectionIndicator(service: _service),
          IconButton(
            tooltip: '重新连接',
            onPressed: _service.configured
                ? () => _service.connect(force: true)
                : null,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'Home Assistant 设置',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const HaSettingsPage()),
            ),
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (!_service.configured) return _notConfigured(context);
    final entities = _filteredEntities;
    return Column(
      children: [
        if (_service.error != null)
          MaterialBanner(
            content: Text(_service.error!),
            actions: [
              TextButton(
                onPressed: () => _service.connect(force: true),
                child: const Text('重试'),
              ),
            ],
          ),
        SizedBox(
          height: 54,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            children: [
              _filterChip('全部', _all),
              _filterChip('常用', _favorites, icon: Icons.star),
              for (final area in _service.areas)
                _filterChip(area.name, area.id,
                    icon: Icons.meeting_room_outlined),
              if (_service.entityViews.any((entity) => entity.areaId == null))
                _filterChip(
                  '未分配',
                  _unassigned,
                  icon: Icons.other_houses_outlined,
                ),
            ],
          ),
        ),
        Expanded(
          child: entities.isEmpty
              ? Center(
                  child: Text(
                    _service.connected
                        ? _selection == _favorites
                            ? '还没有收藏设备\n可在“全部”或房间页面点击星标收藏'
                            : '当前分类没有可显示的实体'
                        : '正在连接 Home Assistant…',
                    textAlign: TextAlign.center,
                  ),
                )
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final columns = _columnCount(constraints.maxWidth);
                    if (_selection == _favorites) {
                      return _buildFavoriteHierarchy(entities, columns);
                    }
                    return GridView.builder(
                      padding: const EdgeInsets.fromLTRB(14, 8, 14, 18),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: columns,
                        mainAxisSpacing: 10,
                        crossAxisSpacing: 10,
                        childAspectRatio: 1.28,
                      ),
                      itemCount: entities.length,
                      itemBuilder: (context, index) => HaEntityTile(
                        entity: entities[index],
                        service: _service,
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  int _columnCount(double width) => width >= 1050
      ? 5
      : width >= 760
          ? 4
          : width >= 520
              ? 3
              : 2;

  Widget _buildFavoriteHierarchy(
    List<HaEntityView> entities,
    int columns,
  ) {
    final hierarchy = <String, Map<String, List<HaEntityView>>>{};
    for (final entity in entities) {
      final room = entity.areaName;
      final device =
          entity.deviceName.trim().isEmpty ? '独立功能' : entity.deviceName.trim();
      hierarchy
          .putIfAbsent(room, () => <String, List<HaEntityView>>{})
          .putIfAbsent(device, () => <HaEntityView>[])
          .add(entity);
    }

    final rooms = hierarchy.keys.toList()..sort();
    for (final devices in hierarchy.values) {
      for (final functions in devices.values) {
        functions.sort((a, b) {
          final domain = a.domain.compareTo(b.domain);
          return domain != 0 ? domain : a.name.compareTo(b.name);
        });
      }
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 18),
      itemCount: rooms.length,
      itemBuilder: (context, roomIndex) {
        final room = rooms[roomIndex];
        final devices = hierarchy[room]!;
        final deviceNames = devices.keys.toList()..sort();
        return Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.meeting_room_outlined,
                    size: 22,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(room, style: Theme.of(context).textTheme.titleLarge),
                ],
              ),
              const SizedBox(height: 6),
              for (final deviceName in deviceNames) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(6, 4, 0, 7),
                  child: Row(
                    children: [
                      const Icon(Icons.devices_other_outlined, size: 17),
                      const SizedBox(width: 7),
                      Text(
                        deviceName,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ],
                  ),
                ),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 1.28,
                  ),
                  itemCount: devices[deviceName]!.length,
                  itemBuilder: (context, index) => HaEntityTile(
                    entity: devices[deviceName]![index],
                    service: _service,
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _notConfigured(BuildContext context) {
    return Center(
      child: Card(
        margin: const EdgeInsets.all(24),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.home_outlined,
                size: 64,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 14),
              Text(
                '配置 Home Assistant',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              const Text(
                '为面板创建普通 HA 用户和长期访问令牌。Token 将保存到 root:root 0600 配置文件。',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const HaSettingsPage()),
                ),
                icon: const Icon(Icons.settings_outlined),
                label: const Text('打开设置'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _filterChip(String label, String value, {IconData? icon}) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        selected: _selection == value,
        onSelected: (_) => setState(() => _selection = value),
        avatar: icon == null ? null : Icon(icon, size: 18),
        label: Text(label),
      ),
    );
  }

  List<HaEntityView> get _filteredEntities {
    final entities = _service.entityViews;
    if (_selection == _favorites) {
      return entities.where((entity) => entity.favorite).toList();
    }
    if (_selection == _unassigned) {
      return entities.where((entity) => entity.areaId == null).toList();
    }
    if (_selection != _all) {
      return entities.where((entity) => entity.areaId == _selection).toList();
    }
    return entities;
  }
}

class _ConnectionIndicator extends StatelessWidget {
  const _ConnectionIndicator({required this.service});

  final HomeAssistantService service;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final (label, color) = switch (service.connectionState) {
      HaConnectionState.connected => ('已连接', Colors.green),
      HaConnectionState.connecting => ('连接中', colors.tertiary),
      HaConnectionState.synchronizing => ('同步中', colors.tertiary),
      HaConnectionState.authenticationFailed => ('认证失败', colors.error),
      HaConnectionState.notConfigured => ('未配置', colors.outline),
      HaConnectionState.disconnected => ('已断开', colors.outline),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, size: 10, color: color),
          const SizedBox(width: 6),
          Text(label),
        ],
      ),
    );
  }
}
