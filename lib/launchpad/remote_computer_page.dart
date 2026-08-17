import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../services/display_service.dart';
import '../services/remote_launchpad_service.dart';
import 'remote_fullscreen.dart';
import 'remote_media_page.dart';
import 'remote_performance_page.dart';

class RemoteComputerPage extends StatefulWidget {
  const RemoteComputerPage({
    super.key,
    required this.computerId,
    required this.computerName,
  });

  final String computerId;
  final String computerName;

  @override
  State<RemoteComputerPage> createState() => _RemoteComputerPageState();
}

class _RemoteComputerPageState extends State<RemoteComputerPage> {
  int _page = 0;
  double _horizontalDragDistance = 0;

  void _onHorizontalDragEnd(DragEndDetails details, int pageCount) {
    final velocity = details.primaryVelocity ?? 0;
    if (_horizontalDragDistance.abs() >= 24 || velocity.abs() >= 180) {
      if ((_horizontalDragDistance < 0 || velocity < -180) &&
          _page + 1 < pageCount) {
        setState(() => _page++);
      } else if ((_horizontalDragDistance > 0 || velocity > 180) && _page > 0) {
        setState(() => _page--);
      }
    }
    _horizontalDragDistance = 0;
  }

  @override
  Widget build(BuildContext context) {
    final service = RemoteLaunchpadService.instance;
    return AnimatedBuilder(
      animation: service,
      builder: (context, _) {
        final actions = service.actionsForComputer(widget.computerId);
        final online = actions.any((action) => action.online);
        final pageCount = actions.isEmpty ? 1 : (actions.length + 8) ~/ 9;
        if (_page >= pageCount) _page = pageCount - 1;
        final pageActions = actions.skip(_page * 9).take(9).toList();
        return Scaffold(
          body: SafeArea(
            child: Column(
              children: [
                _CompactHeader(
                  computerName: widget.computerName,
                  online: online,
                  page: _page,
                  pageCount: pageCount,
                ),
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onHorizontalDragStart: (_) => _horizontalDragDistance = 0,
                    onHorizontalDragUpdate: (details) =>
                        _horizontalDragDistance += details.primaryDelta ?? 0,
                    onHorizontalDragEnd: (details) =>
                        _onHorizontalDragEnd(details, pageCount),
                    onHorizontalDragCancel: () => _horizontalDragDistance = 0,
                    child: actions.isEmpty
                        ? const Center(child: Text('这台电脑尚未注册操作'))
                        : LayoutBuilder(
                            builder: (context, constraints) {
                              const padding = 12.0;
                              const spacing = 10.0;
                              final cellWidth = (constraints.maxWidth -
                                      padding * 2 -
                                      spacing * 2) /
                                  3;
                              final cellHeight = (constraints.maxHeight -
                                      padding * 2 -
                                      spacing * 2) /
                                  3;
                              return GridView.builder(
                                padding: const EdgeInsets.all(padding),
                                physics: const NeverScrollableScrollPhysics(),
                                gridDelegate:
                                    SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 3,
                                  mainAxisSpacing: spacing,
                                  crossAxisSpacing: spacing,
                                  childAspectRatio: cellWidth / cellHeight,
                                ),
                                itemCount: pageActions.length,
                                itemBuilder: (context, index) =>
                                    _RemoteActionCard(
                                  action: pageActions[index],
                                ),
                              );
                            },
                          ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _CompactHeader extends StatelessWidget {
  const _CompactHeader({
    required this.computerName,
    required this.online,
    required this.page,
    required this.pageCount,
  });

  final String computerName;
  final bool online;
  final int page;
  final int pageCount;

  @override
  Widget build(BuildContext context) {
    final scale = DisplayService.instance.scaleFactor;
    final colors = Theme.of(context).colorScheme;
    return SizedBox(
      height: 48 * scale,
      child: Material(
        color: colors.surfaceContainerLow,
        child: Row(
          children: [
            IconButton(
              tooltip: '返回',
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.arrow_back),
            ),
            const SizedBox(width: 2),
            Icon(
              Icons.circle,
              size: 10,
              color: online ? Colors.green : colors.outline,
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                computerName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
            Text(
              online ? '在线' : '离线',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (pageCount > 1) ...[
              const SizedBox(width: 8),
              Icon(
                Icons.swipe,
                size: 18,
                color: colors.onSurfaceVariant,
              ),
              const SizedBox(width: 5),
              Text('${page + 1}/$pageCount'),
              const SizedBox(width: 12),
            ] else
              const SizedBox(width: 12),
          ],
        ),
      ),
    );
  }
}

class _RemoteActionCard extends StatelessWidget {
  const _RemoteActionCard({required this.action});

  final RemoteLaunchpadAction action;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      color: action.online
          ? colors.surfaceContainer
          : colors.surfaceContainerHighest,
      child: InkWell(
        onTap: action.online
            ? () {
                if (action.kind == 'media') {
                  Navigator.of(context).push(
                    remoteFullscreenRoute(
                      RemoteMediaPage(
                        computerId: action.clientId,
                        computerName: action.clientName,
                      ),
                    ),
                  );
                  return;
                }
                if (action.kind == 'performance') {
                  Navigator.of(context).push(
                    remoteFullscreenRoute(
                      RemotePerformancePage(
                        computerId: action.clientId,
                        computerName: action.clientName,
                      ),
                    ),
                  );
                  return;
                }
                final sent = RemoteLaunchpadService.instance.invoke(action);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(sent ? '已发送：${action.name}' : '电脑已经离线'),
                    duration: const Duration(seconds: 1),
                  ),
                );
              }
            : null,
        child: Opacity(
          opacity: action.online ? 1 : 0.42,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Expanded(
                  child: Center(
                    child: _RemoteActionIcon(
                      path: action.iconPath,
                      online: action.online,
                      kind: action.kind,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  action.name,
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: action.online
                        ? colors.onSurface
                        : colors.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RemoteActionIcon extends StatelessWidget {
  const _RemoteActionIcon({
    required this.path,
    required this.online,
    required this.kind,
  });

  final String path;
  final bool online;
  final String kind;

  @override
  Widget build(BuildContext context) {
    final fallback = Icon(
      switch (kind) {
        'media' => Icons.music_note_rounded,
        'performance' => Icons.monitor_heart_outlined,
        _ => Icons.apps,
      },
      size: 54,
      color: Theme.of(context).colorScheme.primary,
    );
    final Widget icon;
    if (path.isEmpty) {
      icon = fallback;
    } else if (path.toLowerCase().endsWith('.svg')) {
      icon = SvgPicture.file(
        File(path),
        width: 58,
        height: 58,
        fit: BoxFit.contain,
        placeholderBuilder: (_) => fallback,
      );
    } else {
      icon = Image.file(
        File(path),
        width: 58,
        height: 58,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => fallback,
      );
    }
    if (online) return icon;
    return ColorFiltered(
      colorFilter: const ColorFilter.matrix(<double>[
        0.2126,
        0.7152,
        0.0722,
        0,
        0,
        0.2126,
        0.7152,
        0.0722,
        0,
        0,
        0.2126,
        0.7152,
        0.0722,
        0,
        0,
        0,
        0,
        0,
        1,
        0,
      ]),
      child: icon,
    );
  }
}
