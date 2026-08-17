/*
Copyright 2025 kozakemi

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

import 'package:flutter/material.dart';

import 'launchpad/file_manager_page.dart';
import 'launchpad/jlink_server_page.dart';
import 'launchpad/jlink_rtt_page.dart';
import 'launchpad/remote_computer_page.dart';
import 'launchpad/serial_preview_page.dart';
import 'launchpad/weather_page.dart';
import 'services/display_service.dart';
import 'services/remote_launchpad_service.dart';

/// 启动台应用图标，上部图标、下部居中显示名称。
class IconItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  const IconItem({
    super.key,
    required this.icon,
    required this.label,
    this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(8),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              icon,
              size: 32,
              color: Theme.of(context).colorScheme.onPrimaryContainer,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              color: Theme.of(context).colorScheme.onSurface,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class LaunchpadPage extends StatelessWidget {
  const LaunchpadPage({super.key});

  final List<IconData> icons = const [
    Icons.folder_outlined,
    Icons.developer_board_outlined,
    Icons.terminal_outlined,
    Icons.usb_outlined,
    Icons.cloud_outlined,
  ];

  final List<String> labels = const [
    '文件管理器',
    'J-Link Server',
    'J-Link RTT',
    '串口预览',
    '天气',
  ];

  List<VoidCallback> getOnTapCallbacks(BuildContext context) {
    return [
      () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const FileManagerPage()),
          ),
      () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const JLinkServerPage()),
          ),
      () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const JLinkRttPage()),
          ),
      () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const SerialPreviewPage()),
          ),
      () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const WeatherPage()),
          ),
    ];
  }

  List<VoidCallback> getOnLongPressCallbacks(BuildContext context) {
    return [
      () => {},
      () => {},
      () => {},
      () => {},
      () => {},
    ];
  }

  @override
  Widget build(BuildContext context) {
    final scale = DisplayService.instance.scaleFactor;
    final iconSize = 24.0 * scale;
    final toolbarHeight = 56.0 * scale;
    final onTapCallbacks = getOnTapCallbacks(context);
    final onLongPressCallbacks = getOnLongPressCallbacks(context);
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('启动台'),
        toolbarHeight: toolbarHeight,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          iconSize: iconSize,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: AnimatedBuilder(
        animation: RemoteLaunchpadService.instance,
        builder: (context, _) {
          final computers = RemoteLaunchpadService.instance.computers;
          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: GridView.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                mainAxisSpacing: 20,
                crossAxisSpacing: 20,
                childAspectRatio: 0.8,
              ),
              itemCount: icons.length + computers.length,
              itemBuilder: (context, index) {
                if (index < icons.length) {
                  return IconItem(
                    icon: icons[index],
                    label: labels[index],
                    onTap: onTapCallbacks[index],
                    onLongPress: onLongPressCallbacks[index],
                  );
                }
                return _RemoteComputerItem(
                  computer: computers[index - icons.length],
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _RemoteComputerItem extends StatelessWidget {
  const _RemoteComputerItem({required this.computer});

  final RemoteLaunchpadComputer computer;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => RemoteComputerPage(
            computerId: computer.id,
            computerName: computer.name,
          ),
        ),
      ),
      onLongPress: computer.online ? null : () => _confirmRemove(context),
      borderRadius: BorderRadius.circular(8),
      child: Opacity(
        opacity: computer.online ? 1 : 0.45,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: computer.online
                    ? colors.primaryContainer
                    : colors.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(
                Icons.computer,
                size: 38,
                color: computer.online
                    ? colors.onPrimaryContainer
                    : colors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              computer.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                color: computer.online
                    ? colors.onSurface
                    : colors.onSurfaceVariant,
              ),
            ),
            Text(
              computer.online
                  ? '${computer.actionCount} 个操作'
                  : '${computer.actionCount} 个操作 · 离线',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 10, color: colors.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmRemove(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('删除“${computer.name}”？'),
        content: const Text('将清除这台离线电脑的操作和图标缓存。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final removed = await RemoteLaunchpadService.instance.removeComputer(
      computer.id,
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(removed ? '已删除 ${computer.name}' : '电脑已重新上线，无法删除'),
      ),
    );
  }
}
