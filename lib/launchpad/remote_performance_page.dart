import 'dart:math';

import 'package:flutter/material.dart';

import '../services/remote_launchpad_service.dart';
import 'remote_fullscreen.dart';

class RemotePerformancePage extends StatefulWidget {
  const RemotePerformancePage({
    super.key,
    required this.computerId,
    required this.computerName,
  });

  final String computerId;
  final String computerName;

  @override
  State<RemotePerformancePage> createState() => _RemotePerformancePageState();
}

class _RemotePerformancePageState extends State<RemotePerformancePage> {
  final _cpuHistory = <double>[];
  final _memoryHistory = <double>[];
  final _gpuHistory = <double>[];
  final _downloadHistory = <double>[];
  final _uploadHistory = <double>[];
  DateTime? _lastSample;

  RemoteLaunchpadService get _service => RemoteLaunchpadService.instance;

  @override
  void initState() {
    super.initState();
    _service.addListener(_recordSample);
    _recordSample();
  }

  @override
  void dispose() {
    _service.removeListener(_recordSample);
    super.dispose();
  }

  void _recordSample() {
    final now = DateTime.now();
    if (_lastSample != null &&
        now.difference(_lastSample!).inMilliseconds < 1000) {
      return;
    }
    final state = _service.performanceStateForComputer(widget.computerId);
    if (!state.available) return;
    _lastSample = now;
    _append(_cpuHistory, state.cpu);
    _append(
      _memoryHistory,
      state.memoryTotal > 0 ? state.memoryUsed / state.memoryTotal : 0,
    );
    _append(_gpuHistory, state.gpu);
    _append(_downloadHistory, state.networkDown);
    _append(_uploadHistory, state.networkUp);
    if (mounted) setState(() {});
  }

  void _append(List<double> values, double value) {
    values.add(value.isFinite ? value : 0);
    if (values.length > 60) values.removeAt(0);
  }

  @override
  Widget build(BuildContext context) {
    final state = _service.performanceStateForComputer(widget.computerId);
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      body: RemoteFullscreen(
        child: SafeArea(
          child: !state.available
              ? Center(
                  child: Text(
                    state.message.isEmpty ? '等待电脑性能数据…' : state.message,
                  ),
                )
              : Padding(
                  padding: const EdgeInsets.fromLTRB(22, 10, 12, 10),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Icon(Icons.monitor_heart, color: colors.primary),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              widget.computerName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                          ),
                          Text(
                            '运行 ${_duration(state.uptime)}',
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        flex: 6,
                        child: Row(
                          children: [
                            Expanded(
                              flex: 6,
                              child: _MetricCard(
                                title: 'CPU ${(state.cpu * 100).round()}%',
                                icon: Icons.memory,
                                child: Column(
                                  children: [
                                    Expanded(
                                      flex: 3,
                                      child: _TrendChart(
                                        values: _cpuHistory,
                                        color: colors.primary,
                                        fill: true,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Expanded(
                                      flex: 4,
                                      child: GridView.builder(
                                        physics:
                                            const NeverScrollableScrollPhysics(),
                                        gridDelegate:
                                            const SliverGridDelegateWithFixedCrossAxisCount(
                                          crossAxisCount: 4,
                                          childAspectRatio: 3.5,
                                          mainAxisSpacing: 3,
                                          crossAxisSpacing: 8,
                                        ),
                                        itemCount: state.cores.length,
                                        itemBuilder: (_, index) => _CoreBar(
                                          index: index,
                                          value: state.cores[index],
                                        ),
                                      ),
                                    ),
                                    if (state.cpuName.isNotEmpty)
                                      Align(
                                        alignment: Alignment.centerLeft,
                                        child: Text(
                                          state.cpuName,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall,
                                        ),
                                      ),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            'Load ${state.load.map((v) => v.toStringAsFixed(2)).join('  ')}',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall,
                                          ),
                                        ),
                                        if (state.temperature > 0)
                                          Text(
                                            '封装 ${state.temperature.toStringAsFixed(0)}°C',
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall,
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              flex: 4,
                              child: Column(
                                children: [
                                  Expanded(
                                    child: _MetricCard(
                                      title: state.gpuAvailable
                                          ? '${state.gpuName}  ${(state.gpu * 100).round()}%'
                                          : 'GPU',
                                      icon: Icons.developer_board,
                                      child: state.gpuAvailable
                                          ? Column(
                                              children: [
                                                Expanded(
                                                  child: _TrendChart(
                                                    values: _gpuHistory,
                                                    color: colors.tertiary,
                                                    fill: true,
                                                  ),
                                                ),
                                                Text(
                                                  _gpuDetails(state),
                                                  maxLines: 2,
                                                  textAlign: TextAlign.center,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .bodySmall,
                                                ),
                                              ],
                                            )
                                          : const Center(
                                              child: Text('未检测到可读取的 GPU'),
                                            ),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Expanded(
                                    child: _MetricCard(
                                      title:
                                          '内存 ${_percent(state.memoryUsed, state.memoryTotal)}',
                                      icon: Icons.storage,
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: _TrendChart(
                                              values: _memoryHistory,
                                              color: colors.secondary,
                                              fill: true,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            '${_bytes(state.memoryUsed)}\n'
                                            '/ ${_bytes(state.memoryTotal)}',
                                            textAlign: TextAlign.right,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        flex: 3,
                        child: Row(
                          children: [
                            Expanded(
                              flex: 4,
                              child: _MetricCard(
                                title:
                                    '磁盘 /  ${_percent(state.diskUsed, state.diskTotal)}',
                                icon: Icons.storage_outlined,
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    LinearProgressIndicator(
                                      value: state.diskTotal > 0
                                          ? state.diskUsed / state.diskTotal
                                          : 0,
                                      minHeight: 12,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    const SizedBox(height: 10),
                                    Text(
                                      '${_bytes(state.diskUsed)} / '
                                      '${_bytes(state.diskTotal)}',
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              flex: 6,
                              child: _MetricCard(
                                title:
                                    '网络  ↓ ${_rate(state.networkDown)}  ↑ ${_rate(state.networkUp)}',
                                icon: Icons.swap_vert,
                                child: _TrendChart(
                                  values: _downloadHistory,
                                  secondaryValues: _uploadHistory,
                                  color: colors.primary,
                                  secondaryColor: colors.tertiary,
                                  normalized: false,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  String _duration(double seconds) {
    final value = seconds.round();
    return '${value ~/ 3600}h ${(value % 3600) ~/ 60}m';
  }

  String _percent(int used, int total) =>
      total > 0 ? '${(used / total * 100).round()}%' : '0%';

  String _bytes(num value) {
    const gib = 1024 * 1024 * 1024;
    return '${(value / gib).toStringAsFixed(1)} GiB';
  }

  String _rate(double value) {
    if (value >= 1024 * 1024) {
      return '${(value / 1024 / 1024).toStringAsFixed(1)} MiB/s';
    }
    return '${(value / 1024).toStringAsFixed(1)} KiB/s';
  }

  String _gpuDetails(RemotePerformanceState state) {
    final details = <String>[];
    if (state.gpuFrequencyMax > 0) {
      details.add(
        '${state.gpuFrequency.toStringAsFixed(0)} / '
        '${state.gpuFrequencyMax.toStringAsFixed(0)} MHz',
      );
    }
    if (state.gpuMemoryShared && state.gpuMemoryTotal > 0) {
      details.add('共享内存上限 ${_bytes(state.gpuMemoryTotal)}');
    } else if (state.gpuMemoryTotal > 0) {
      details.add(
        '${_bytes(state.gpuMemoryUsed)} / ${_bytes(state.gpuMemoryTotal)}',
      );
    }
    if (state.gpuTemperature > 0) {
      details.add(
        '${state.gpuMemoryShared ? '封装' : 'GPU'} '
        '${state.gpuTemperature.toStringAsFixed(0)}°C',
      );
    }
    if (state.gpuPower > 0) {
      details.add('${state.gpuPower.toStringAsFixed(1)}W');
    }
    if (state.gpuMessage.isNotEmpty) details.add(state.gpuMessage);
    return details.isEmpty ? '暂无更多传感器数据' : details.join('  ·  ');
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.title,
    required this.icon,
    required this.child,
  });

  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      color: Theme.of(context).colorScheme.surfaceContainer,
      child: Padding(
        padding: const EdgeInsets.all(9),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 17),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 5),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}

class _CoreBar extends StatelessWidget {
  const _CoreBar({required this.index, required this.value});
  final int index;
  final double value;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      children: [
        SizedBox(width: 24, child: Text('C$index')),
        Expanded(
          child: LinearProgressIndicator(
            value: value.clamp(0, 1),
            minHeight: 7,
            color: value > .8
                ? colors.error
                : value > .5
                    ? colors.tertiary
                    : colors.primary,
            borderRadius: BorderRadius.circular(5),
          ),
        ),
        SizedBox(
          width: 31,
          child: Text(
            '${(value * 100).round()}',
            textAlign: TextAlign.right,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}

class _TrendChart extends StatelessWidget {
  const _TrendChart({
    required this.values,
    required this.color,
    this.secondaryValues,
    this.secondaryColor,
    this.fill = false,
    this.normalized = true,
  });

  final List<double> values;
  final List<double>? secondaryValues;
  final Color color;
  final Color? secondaryColor;
  final bool fill;
  final bool normalized;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _TrendPainter(
        values: values,
        secondaryValues: secondaryValues,
        color: color,
        secondaryColor: secondaryColor,
        gridColor: Theme.of(context).colorScheme.outlineVariant,
        fill: fill,
        normalized: normalized,
      ),
      child: const SizedBox.expand(),
    );
  }
}

class _TrendPainter extends CustomPainter {
  const _TrendPainter({
    required this.values,
    required this.color,
    required this.gridColor,
    required this.fill,
    required this.normalized,
    this.secondaryValues,
    this.secondaryColor,
  });

  final List<double> values;
  final List<double>? secondaryValues;
  final Color color;
  final Color gridColor;
  final Color? secondaryColor;
  final bool fill;
  final bool normalized;

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = gridColor.withAlpha(90)
      ..strokeWidth = 1;
    for (var index = 1; index < 4; index++) {
      final y = size.height * index / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    final maximum = normalized
        ? 1.0
        : max(
            1.0,
            [
              ...values,
              ...?secondaryValues,
            ].fold<double>(0, max),
          );
    _drawSeries(canvas, size, values, color, maximum, fill);
    if (secondaryValues != null) {
      _drawSeries(
        canvas,
        size,
        secondaryValues!,
        secondaryColor ?? color,
        maximum,
        false,
      );
    }
  }

  void _drawSeries(
    Canvas canvas,
    Size size,
    List<double> data,
    Color seriesColor,
    double maximum,
    bool drawFill,
  ) {
    if (data.length < 2) return;
    final path = Path();
    for (var index = 0; index < data.length; index++) {
      final x = size.width * index / max(1, data.length - 1);
      final y = size.height * (1 - (data[index] / maximum).clamp(0.0, 1.0));
      if (index == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    if (drawFill) {
      final fillPath = Path.from(path)
        ..lineTo(size.width, size.height)
        ..lineTo(0, size.height)
        ..close();
      canvas.drawPath(
        fillPath,
        Paint()..color = seriesColor.withAlpha(42),
      );
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = seriesColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _TrendPainter oldDelegate) => true;
}
