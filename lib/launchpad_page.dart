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
import 'launchpad/serial_preview_page.dart';
import 'services/display_service.dart';

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
    Icons.usb_outlined,
  ];

  final List<String> labels = const [
    '文件管理器',
    'J-Link Server',
    '串口预览',
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
            MaterialPageRoute(builder: (_) => const SerialPreviewPage()),
          ),
    ];
  }

  List<VoidCallback> getOnLongPressCallbacks(BuildContext context) {
    return [
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
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: GridView.builder(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 4, // 每行显示4个
            mainAxisSpacing: 20, // 垂直间距
            crossAxisSpacing: 20, // 水平间距
            childAspectRatio: 0.8, // 宽高比
          ),
          itemCount: icons.length,
          itemBuilder: (context, index) {
            return IconItem(
              icon: icons[index],
              label: labels[index],
              onTap: onTapCallbacks[index], // 从列表中获取回调
              onLongPress: onLongPressCallbacks[index], // 从列表中获取回调
            );
          },
        ),
      ),
    );
  }
}
