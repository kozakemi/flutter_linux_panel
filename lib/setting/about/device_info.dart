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

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:device_info_plus/device_info_plus.dart';
import '../../services/display_service.dart';

class DeviceInfoPage extends StatefulWidget {
  const DeviceInfoPage({super.key});

  @override
  State<DeviceInfoPage> createState() => _DeviceInfoPageState();
}

class _DeviceInfoPageState extends State<DeviceInfoPage> {
  Map<String, dynamic>? _info;
  String? _error;
  bool _loading = true;

  Future<void> _loadInfo() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final info = await _collectInfo();
      setState(() {
        _info = info;
      });
    } catch (e) {
      setState(() {
        _error = '无法获取设备信息: $e';
      });
    } finally {
      setState(() {
        _loading = false;
      });
    }
  }

  Future<Map<String, dynamic>> _collectInfo() async {
    final plugin = DeviceInfoPlugin();
    if (kIsWeb) {
      final info = await plugin.webBrowserInfo;
      return info.toMap();
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        final info = await plugin.androidInfo;
        return info.toMap();
      case TargetPlatform.iOS:
        final info = await plugin.iosInfo;
        return info.toMap();
      case TargetPlatform.linux:
        final info = await plugin.linuxInfo;
        return info.toMap();
      case TargetPlatform.macOS:
        final info = await plugin.macOsInfo;
        return info.toMap();
      case TargetPlatform.windows:
        final info = await plugin.windowsInfo;
        return info.toMap();
      case TargetPlatform.fuchsia:
        return {'platform': 'fuchsia'};
    }
  }

  @override
  void initState() {
    super.initState();
    unawaited(_loadInfo());
  }

  Widget _buildSection(List<Widget> tiles) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Material(
        color: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: ListTile.divideTiles(
            context: context,
            tiles: tiles,
          ).toList(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scale = DisplayService.instance.scaleFactor;
    final iconSize = 24.0 * scale;
    final toolbarHeight = 56.0 * scale;
    final infoMap = _info ?? {};
    final keys = infoMap.keys.map((k) => k.toString()).toList()..sort();

    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F7),
      appBar: AppBar(
        title: const Text('设备信息'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        toolbarHeight: toolbarHeight,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          iconSize: iconSize,
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            tooltip: '刷新',
            icon: const Icon(Icons.refresh),
            iconSize: iconSize,
            onPressed: _loadInfo,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Text(
                      _error!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                )
              : ListView(
                  children: [
                    const SizedBox(height: 24),
                    _buildSection(
                      keys
                          .map((k) => ListTile(
                                title: Text(k),
                                subtitle: Text('${infoMap[k]}'),
                              ))
                          .toList(),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
    );
  }
}