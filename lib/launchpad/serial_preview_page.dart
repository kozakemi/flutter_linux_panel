import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../services/display_service.dart';
import 'services/serial_port_service.dart';

class SerialPreviewPage extends StatefulWidget {
  const SerialPreviewPage({super.key});

  @override
  State<SerialPreviewPage> createState() => _SerialPreviewPageState();
}

class _SerialPreviewPageState extends State<SerialPreviewPage> {
  static const List<int> _baudRates = <int>[
    1200,
    2400,
    4800,
    9600,
    19200,
    38400,
    57600,
    115200,
    230400,
    460800,
    921600,
  ];

  final SerialPortService _service = SerialPortService.instance;
  final ScrollController _verticalScrollController = ScrollController();
  final ScrollController _horizontalScrollController = ScrollController();
  List<String> _devices = const <String>[];
  String? _selectedDevice;
  int _selectedBaudRate = 115200;
  SerialParity _selectedParity = SerialParity.none;
  bool _scanning = false;
  int _previousOutputRevision = 0;

  @override
  void initState() {
    super.initState();
    _selectedDevice = _service.device;
    _selectedBaudRate = _service.baudRate;
    _selectedParity = _service.parity;
    _previousOutputRevision = _service.outputRevision;
    _service.addListener(_handleServiceChanged);
    unawaited(_scanDevices());
  }

  @override
  void dispose() {
    _service.removeListener(_handleServiceChanged);
    _verticalScrollController.dispose();
    _horizontalScrollController.dispose();
    super.dispose();
  }

  Future<void> _scanDevices() async {
    if (_scanning) return;
    setState(() => _scanning = true);
    final devices = await _service.scanDevices(force: true);
    if (!mounted) return;
    setState(() {
      _devices = devices;
      if (_service.device != null && !_devices.contains(_service.device)) {
        _devices = <String>[_service.device!, ..._devices];
      }
      if (_selectedDevice == null || !_devices.contains(_selectedDevice)) {
        _selectedDevice = _devices.isEmpty ? null : _devices.first;
      }
      _scanning = false;
    });
  }

  void _handleServiceChanged() {
    if (!mounted) return;
    final revision = _service.outputRevision;
    final shouldScroll = revision > _previousOutputRevision;
    _previousOutputRevision = revision;
    setState(() {});
    if (!shouldScroll) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_verticalScrollController.hasClients) return;
      _verticalScrollController.animateTo(
        _verticalScrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOut,
      );
    });
  }

  void _handleHorizontalDrag(DragUpdateDetails details) {
    if (!_horizontalScrollController.hasClients) return;
    final position = _horizontalScrollController.position;
    final target = (_horizontalScrollController.offset - details.delta.dx)
        .clamp(position.minScrollExtent, position.maxScrollExtent);
    _horizontalScrollController.jumpTo(target);
  }

  Future<void> _openPort() async {
    final device = _selectedDevice;
    if (device == null) return;
    await _service.openPort(
      device: device,
      baudRate: _selectedBaudRate,
      parity: _selectedParity,
    );
  }

  @override
  Widget build(BuildContext context) {
    final scale = DisplayService.instance.scaleFactor;
    final controlsEnabled = !_service.open && !_service.opening;
    final output = _service.output;
    final statusColor = _service.open
        ? Colors.green
        : _service.opening
            ? Colors.orange
            : Colors.grey;
    final statusText = _service.open
        ? '已打开 ${_service.device}'
        : _service.opening
            ? '正在打开'
            : '未打开';

    return Scaffold(
      appBar: AppBar(
        title: const Text('串口预览'),
        toolbarHeight: 56 * scale,
        actions: [
          IconButton(
            tooltip: '重新扫描串口',
            onPressed: _scanning ? null : _scanDevices,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: '清空输出',
            onPressed: _service.clearOutput,
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
                  children: [
                    Row(
                      children: [
                        Icon(Icons.circle, size: 12, color: statusColor),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            statusText,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: DropdownButtonFormField<String>(
                            value: _selectedDevice,
                            decoration: const InputDecoration(
                              labelText: '串口通道',
                              border: OutlineInputBorder(),
                            ),
                            items: _devices
                                .map(
                                  (device) => DropdownMenuItem<String>(
                                    value: device,
                                    child: Text(device),
                                  ),
                                )
                                .toList(),
                            onChanged: controlsEnabled
                                ? (value) =>
                                    setState(() => _selectedDevice = value)
                                : null,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            value: _selectedBaudRate,
                            decoration: const InputDecoration(
                              labelText: '波特率',
                              border: OutlineInputBorder(),
                            ),
                            items: _baudRates
                                .map(
                                  (rate) => DropdownMenuItem<int>(
                                    value: rate,
                                    child: Text('$rate'),
                                  ),
                                )
                                .toList(),
                            onChanged: controlsEnabled
                                ? (value) {
                                    if (value != null) {
                                      setState(
                                        () => _selectedBaudRate = value,
                                      );
                                    }
                                  }
                                : null,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DropdownButtonFormField<SerialParity>(
                            value: _selectedParity,
                            decoration: const InputDecoration(
                              labelText: '校验位',
                              border: OutlineInputBorder(),
                            ),
                            items: SerialParity.values
                                .map(
                                  (parity) => DropdownMenuItem<SerialParity>(
                                    value: parity,
                                    child: Text(parity.label),
                                  ),
                                )
                                .toList(),
                            onChanged: controlsEnabled
                                ? (value) {
                                    if (value != null) {
                                      setState(
                                        () => _selectedParity = value,
                                      );
                                    }
                                  }
                                : null,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        FilledButton.icon(
                          onPressed: controlsEnabled && _selectedDevice != null
                              ? _openPort
                              : null,
                          icon: const Icon(Icons.usb),
                          label: const Text('打开串口'),
                        ),
                        const SizedBox(width: 12),
                        OutlinedButton.icon(
                          onPressed: _service.open || _service.opening
                              ? _service.closePort
                              : null,
                          icon: const Icon(Icons.stop),
                          label: const Text('关闭串口'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              '接收数据',
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
                child: Scrollbar(
                  controller: _verticalScrollController,
                  thumbVisibility: true,
                  child: SingleChildScrollView(
                    controller: _verticalScrollController,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      dragStartBehavior: DragStartBehavior.down,
                      onHorizontalDragUpdate: _handleHorizontalDrag,
                      child: Scrollbar(
                        controller: _horizontalScrollController,
                        thumbVisibility: true,
                        notificationPredicate: (notification) =>
                            notification.metrics.axis == Axis.horizontal,
                        child: SingleChildScrollView(
                          controller: _horizontalScrollController,
                          scrollDirection: Axis.horizontal,
                          physics: const NeverScrollableScrollPhysics(),
                          child: Text(
                            output,
                            softWrap: false,
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
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
