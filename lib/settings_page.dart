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

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'setting/wifi_page.dart';
import 'setting/bluetooth_page.dart';
import 'setting/display_page.dart';
import 'setting/about_page.dart';
import 'setting/developer_page.dart';
import 'setting/wallpaper_settings_page.dart';
import 'setting/remote_web_settings_page.dart';
import 'services/display_service.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool wifiEnabled = true;
  bool bluetoothEnabled = false;

  void _showNotImplemented(String title) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$title 功能暂未实现'),
        duration: const Duration(milliseconds: 1200),
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title,
        style: TextStyle(
          color: Colors.grey.shade600,
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _icon(IconData iconData) {
    return Icon(
      iconData,
      size: 24,
    );
  }

  Widget _section(List<Widget> tiles) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: ListTile.divideTiles(
          context: context,
          tiles: tiles,
          color: Theme.of(context).dividerColor.withOpacity(0.1),
        ).toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scale = DisplayService.instance.scaleFactor;
    final iconSize = 24.0 * scale;
    final toolbarHeight = 56.0 * scale;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('设置'),
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
          _sectionHeader('连接'),
          _section([
            ListTile(
              leading: _icon(Icons.wifi),
              title: const Text('Wi‑Fi'),
              trailing: const Icon(Icons.chevron_right, size: 20),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const WiFiSettingsPage()),
              ),
            ),
            ListTile(
              leading: _icon(Icons.bluetooth),
              title: const Text('蓝牙'),
              trailing: const Icon(Icons.chevron_right, size: 20),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                    builder: (_) => const BluetoothSettingsPage()),
              ),
            ),
          ]),
          const SizedBox(height: 24),
          _sectionHeader('显示和声音'),
          _section([
            ListTile(
              leading: _icon(Icons.display_settings),
              title: const Text('显示设置'),
              trailing: const Icon(Icons.chevron_right, size: 20),
              onTap: () {
                // #region debug-point A:display-settings-navigation
                (() async {
                  try {
                    var debugServerUrl = 'http://198.18.0.1:7778/event';
                    var debugSessionId = 'display-settings-crash';
                    try {
                      final env = await File(
                        '.dbg/display-settings-crash.env',
                      ).readAsString();
                      for (final line in env.split('\n')) {
                        if (line.startsWith('DEBUG_SERVER_URL=')) {
                          debugServerUrl = line.substring(
                            'DEBUG_SERVER_URL='.length,
                          );
                        } else if (line.startsWith('DEBUG_SESSION_ID=')) {
                          debugSessionId = line.substring(
                            'DEBUG_SESSION_ID='.length,
                          );
                        }
                      }
                    } catch (_) {}
                    final client = HttpClient();
                    final req = await client.postUrl(Uri.parse(debugServerUrl));
                    req.headers.contentType = ContentType.json;
                    req.write(
                      jsonEncode({
                        'sessionId': debugSessionId,
                        'runId': 'pre-fix',
                        'hypothesisId': 'A',
                        'location': 'lib/settings_page.dart:131',
                        'msg': '[DEBUG] display settings tap before push',
                        'data': {'route': 'DisplaySettingsPage'},
                        'ts': DateTime.now().millisecondsSinceEpoch,
                      }),
                    );
                    await req.close();
                    client.close();
                  } catch (_) {}
                })();
                // #endregion
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const DisplaySettingsPage(),
                  ),
                );
              },
            ),
            ListTile(
              leading: _icon(Icons.volume_up),
              title: const Text('声音设置'),
              trailing: const Icon(Icons.chevron_right, size: 20),
              onTap: () => _showNotImplemented('声音设置'),
            ),
            ListTile(
              leading: _icon(Icons.wallpaper),
              title: const Text('壁纸和主题色'),
              trailing: const Icon(Icons.chevron_right, size: 20),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const WallpaperSettingsPage(),
                ),
              ),
            ),
          ]),
          const SizedBox(height: 24),
          _sectionHeader('系统'),
          _section([
            ListTile(
              leading: _icon(Icons.language),
              title: const Text('远程 Web 设置'),
              subtitle: const Text('通过手机或电脑设置壁纸'),
              trailing: const Icon(Icons.chevron_right, size: 20),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const RemoteWebSettingsPage(),
                ),
              ),
            ),
            ListTile(
              leading: _icon(Icons.battery_std),
              title: const Text('电池管理'),
              trailing: const Icon(Icons.chevron_right, size: 20),
              onTap: () => _showNotImplemented('电池管理'),
            ),
            ListTile(
              leading: _icon(Icons.keyboard),
              title: const Text('键盘设置'),
              trailing: const Icon(Icons.chevron_right, size: 20),
              onTap: () => _showNotImplemented('键盘设置'),
            ),
          ]),
          const SizedBox(height: 24),
          _sectionHeader('关于'),
          _section([
            ListTile(
              leading: _icon(Icons.info_outline),
              title: const Text('关于'),
              trailing: const Icon(Icons.chevron_right, size: 20),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AboutPage()),
              ),
            ),
            ListTile(
              leading: _icon(Icons.developer_mode),
              title: const Text('开发者'),
              trailing: const Icon(Icons.chevron_right, size: 20),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const DeveloperPage()),
              ),
            ),
          ]),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
