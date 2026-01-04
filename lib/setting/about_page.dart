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
import 'about/software_info.dart';
import 'about/device_info.dart';
import '../services/display_service.dart';

class AboutPage extends StatefulWidget {
  const AboutPage({super.key});

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  @override
  Widget build(BuildContext context) {
    final scale = DisplayService.instance.scaleFactor;
    final iconSize = 24.0 * scale;
    final toolbarHeight = 56.0 * scale;
    return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: AppBar(
          title: const Text('关于'),
          toolbarHeight: toolbarHeight,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            iconSize: iconSize,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        body: ListView(
          children: [
            const SizedBox(height: 8),
            Card(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: ListTile.divideTiles(
                    context: context,
                    tiles: [
                      ListTile(
                      leading: const Icon(Icons.phone_android),
                        title: const Text('设备信息'),
                      trailing: const Icon(Icons.chevron_right, size: 20),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const DeviceInfoPage()),
                        ),
                      ),
                      ListTile(
                      leading: const Icon(Icons.info_outline),
                        title: const Text('软件信息'),
                      trailing: const Icon(Icons.chevron_right, size: 20),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const SoftwareInfoPage()),
                        ),
                      ),
                    ],
                  color: Theme.of(context).dividerColor.withOpacity(0.1),
                  ).toList(),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ));
  }
}
