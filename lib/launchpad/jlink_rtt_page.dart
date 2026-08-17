import 'package:flutter/material.dart';

import '../services/display_service.dart';
import 'services/jlink_rtt_service.dart';

class JLinkRttPage extends StatefulWidget {
  const JLinkRttPage({super.key});

  @override
  State<JLinkRttPage> createState() => _JLinkRttPageState();
}

class _JLinkRttPageState extends State<JLinkRttPage> {
  final JLinkRttService _service = JLinkRttService.instance;
  final TextEditingController _deviceController = TextEditingController();
  final TextEditingController _sendController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  String _interface = 'SWD';
  int _speed = 4000;
  bool _appendNewline = true;
  int _revision = 0;

  @override
  void initState() {
    super.initState();
    _deviceController.text = _service.device;
    _interface = _service.interface;
    _speed = _service.speed;
    _revision = _service.outputRevision;
    _service.addListener(_changed);
  }

  @override
  void dispose() {
    _service.removeListener(_changed);
    _deviceController.dispose();
    _sendController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _changed() {
    if (!mounted) return;
    final shouldScroll = _service.outputRevision > _revision;
    _revision = _service.outputRevision;
    setState(() {});
    if (shouldScroll) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(
            _scrollController.position.maxScrollExtent,
          );
        }
      });
    }
  }

  void _send() {
    final value = _sendController.text;
    if (value.isEmpty) return;
    try {
      _service.send('$value${_appendNewline ? '\n' : ''}');
      _sendController.clear();
    } catch (error) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scale = DisplayService.instance.scaleFactor;
    final controlsEnabled = !_service.running && !_service.starting;
    return Scaffold(
      appBar: AppBar(
        title: const Text('J-Link RTT'),
        toolbarHeight: 56 * scale,
        actions: [
          IconButton(
            onPressed: _service.clearOutput,
            tooltip: '清空输出',
            icon: const Icon(Icons.delete_sweep_outlined),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: _deviceController,
                        enabled: controlsEnabled,
                        decoration: const InputDecoration(
                          labelText: '芯片型号',
                          hintText: '例如 STM32F407VG',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    DropdownButton<String>(
                      value: _interface,
                      items: const [
                        DropdownMenuItem(value: 'SWD', child: Text('SWD')),
                        DropdownMenuItem(value: 'JTAG', child: Text('JTAG')),
                      ],
                      onChanged: controlsEnabled
                          ? (value) => setState(() => _interface = value!)
                          : null,
                    ),
                    const SizedBox(width: 8),
                    DropdownButton<int>(
                      value: _speed,
                      items: const [1000, 2000, 4000, 8000]
                          .map(
                            (value) => DropdownMenuItem(
                              value: value,
                              child: Text('$value kHz'),
                            ),
                          )
                          .toList(),
                      onChanged: controlsEnabled
                          ? (value) => setState(() => _speed = value!)
                          : null,
                    ),
                    const SizedBox(width: 12),
                    FilledButton.icon(
                      onPressed: controlsEnabled
                          ? () => _service.start(
                                device: _deviceController.text,
                                interface: _interface,
                                speed: _speed,
                              )
                          : null,
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('启动'),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: _service.running || _service.starting
                          ? _service.stop
                          : null,
                      icon: const Icon(Icons.stop),
                      label: const Text('停止'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xff111318),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SingleChildScrollView(
                  controller: _scrollController,
                  child: SelectionArea(
                    child: Text(
                      _service.output,
                      softWrap: true,
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
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _sendController,
                    enabled: _service.connected,
                    onSubmitted: (_) => _send(),
                    decoration: const InputDecoration(
                      hintText: '发送到 RTT 通道 0',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                Checkbox(
                  value: _appendNewline,
                  onChanged: (value) =>
                      setState(() => _appendNewline = value ?? true),
                ),
                const Text('换行'),
                IconButton.filled(
                  onPressed: _service.connected ? _send : null,
                  tooltip: '发送',
                  icon: const Icon(Icons.send),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
