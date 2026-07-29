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

import '../services/display_service.dart';
import 'services/jlink_server_service.dart';

class JLinkServerPage extends StatefulWidget {
  const JLinkServerPage({super.key});

  @override
  State<JLinkServerPage> createState() => _JLinkServerPageState();
}

class _JLinkServerPageState extends State<JLinkServerPage> {
  final ScrollController _logScrollController = ScrollController();
  final JLinkServerService _service = JLinkServerService.instance;
  int _previousLogCount = 0;

  @override
  void initState() {
    super.initState();
    _previousLogCount = _service.logs.length;
    _service.addListener(_handleServiceChanged);
    _service.loadAddresses();
  }

  @override
  void dispose() {
    _service.removeListener(_handleServiceChanged);
    _logScrollController.dispose();
    super.dispose();
  }

  void _handleServiceChanged() {
    if (!mounted) return;
    final shouldScroll = _service.logs.length > _previousLogCount;
    _previousLogCount = _service.logs.length;
    setState(() {});
    if (!shouldScroll) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_logScrollController.hasClients) return;
      _logScrollController.animateTo(
        _logScrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final scale = DisplayService.instance.scaleFactor;
    final statusColor = _service.running
        ? Colors.green
        : _service.starting
            ? Colors.orange
            : Colors.grey;
    final statusText = _service.running
        ? '运行中'
        : _service.starting
            ? '启动中'
            : '已停止';

    return Scaffold(
      appBar: AppBar(
        title: const Text('J-Link Server'),
        toolbarHeight: 56 * scale,
        actions: [
          IconButton(
            tooltip: '清空日志',
            onPressed: _service.clearLogs,
            icon: const Icon(Icons.delete_sweep_outlined),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.circle, size: 12, color: statusColor),
                        const SizedBox(width: 8),
                        Text(
                          statusText,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const Spacer(),
                        const Text('端口 19020'),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      '连接地址',
                      style: TextStyle(fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 4),
                    if (_service.addresses.isEmpty)
                      const Text('正在获取本机 IPv4 地址…')
                    else
                      for (final address in _service.addresses)
                        SelectableText(
                          '$address:${JLinkServerService.port}',
                        ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        FilledButton.icon(
                          onPressed: _service.running || _service.starting
                              ? null
                              : _service.start,
                          icon: const Icon(Icons.play_arrow),
                          label: const Text('启动'),
                        ),
                        const SizedBox(width: 12),
                        OutlinedButton.icon(
                          onPressed: _service.running || _service.starting
                              ? _service.stop
                              : null,
                          icon: const Icon(Icons.stop),
                          label: const Text('停止'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              '运行日志',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xff111318),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SelectionArea(
                  child: ListView.builder(
                    controller: _logScrollController,
                    itemCount: _service.logs.length,
                    itemBuilder: (context, index) => Text(
                      _service.logs[index],
                      style: const TextStyle(
                        color: Color(0xffd6e1e8),
                        fontFamily: 'monospace',
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
