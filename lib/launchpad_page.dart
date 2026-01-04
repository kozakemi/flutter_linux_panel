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
import 'package:flutter_svg/flutter_svg.dart';
import 'launchpad/music_app.dart';
import 'services/display_service.dart';

/**
 * 图标组件
 * 上部图片 下部居中图标名称
 */
class IconItem extends StatelessWidget {
  final String iconPath; // 改为String类型存储SVG路径
  final String label;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  const IconItem({
    Key? key,
    required this.iconPath,
    required this.label,
    this.onTap,
    this.onLongPress,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(8),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 使用 SvgPicture 显示 SVG 图标
          SvgPicture.asset(
            iconPath,
            width: 48,
            height: 48,
            // colorFilter: const ColorFilter.mode(
            //   Colors.blue,
            //   BlendMode.srcIn,
            // ),
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
  const LaunchpadPage({Key? key}) : super(key: key);

  // 定义SVG图标路径（使用String类型）
  final List<String> iconPaths = const [
    'source/app_ico/FilesandFolders.svg',
    'source/app_ico/Music.svg',
    'source/app_ico/video-02-1.svg',
  ];

  final List<String> labels = const [
    '文件管理器',
    '音乐播放器',
    '视频播放器',
  ];

  List<VoidCallback> getOnTapCallbacks(BuildContext context) {
    return [
      () => {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('文件管理器暂未实现')),
            )
          },
      () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const MusicAppPage()),
          ),
      () => {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('视频播放器暂未实现')),
            )
          },
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
          itemCount: iconPaths.length,
          itemBuilder: (context, index) {
            return IconItem(
              iconPath: iconPaths[index],
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
