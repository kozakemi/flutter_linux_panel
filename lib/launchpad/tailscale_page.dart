import 'dart:async';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../services/display_service.dart';
import 'services/tailscale_service.dart';

class TailscalePage extends StatefulWidget {
  const TailscalePage({super.key});

  @override
  State<TailscalePage> createState() => _TailscalePageState();
}

class _TailscalePageState extends State<TailscalePage> {
  final TailscaleService _service = TailscaleService.instance;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _service.addListener(_changed);
    unawaited(_service.refresh());
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 4),
      (_) => unawaited(_service.refresh()),
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _service.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final scale = DisplayService.instance.scaleFactor;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tailscale'),
        toolbarHeight: 56 * scale,
        actions: [
          IconButton(
            tooltip: '刷新状态',
            onPressed: _service.refreshing ? null : _service.refresh,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: '清空日志',
            onPressed: _service.clearLogs,
            icon: const Icon(Icons.delete_sweep_outlined),
          ),
        ],
      ),
      body: !_service.installed
          ? _buildNotInstalled(context)
          : LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 720;
                final status = _buildStatusAndActions(context);
                final detail = _buildLoginAndLogs(context, expandLogs: wide);
                if (!wide) {
                  return ListView(
                    padding: const EdgeInsets.all(16),
                    children: [status, const SizedBox(height: 12), detail],
                  );
                }
                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(flex: 5, child: status),
                      const SizedBox(width: 12),
                      Expanded(flex: 4, child: detail),
                    ],
                  ),
                );
              },
            ),
    );
  }

  Widget _buildNotInstalled(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.vpn_key_off_outlined, size: 64),
          const SizedBox(height: 12),
          Text(
            '未找到 Tailscale',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 6),
          Text(_service.error ?? '请确认系统已安装 tailscale 和 tailscaled'),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: _service.refresh,
            icon: const Icon(Icons.refresh),
            label: const Text('重新检测'),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusAndActions(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final statusColor = _service.connected
        ? Colors.green
        : _service.needsLogin
            ? colors.tertiary
            : colors.outline;
    return SingleChildScrollView(
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
                        _statusText,
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const Spacer(),
                      if (_service.refreshing)
                        const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _detailRow('守护进程', _service.daemonActive ? '运行中' : '已停止'),
                  _detailRow('设备名称', _service.hostName),
                  _detailRow('MagicDNS', _service.dnsName),
                  _detailRow('Tailnet', _service.tailnetName),
                  _detailRow(
                    'Tailscale IP',
                    _service.addresses.isEmpty
                        ? '—'
                        : _service.addresses.join('\n'),
                  ),
                  if (_service.error != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      _service.error!,
                      style: TextStyle(color: colors.error),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('连接控制', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      FilledButton.icon(
                        onPressed: _service.busy || _service.authPending
                            ? null
                            : _service.login,
                        icon: const Icon(Icons.login),
                        label: const Text('登录'),
                      ),
                      FilledButton.tonalIcon(
                        onPressed: _service.busy ||
                                _service.authPending ||
                                _service.connected
                            ? null
                            : _service.connect,
                        icon: const Icon(Icons.power_settings_new),
                        label: const Text('连接'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _service.busy || !_service.connected
                            ? null
                            : _service.disconnect,
                        icon: const Icon(Icons.link_off),
                        label: const Text('断开'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _service.authPending
                            ? _service.cancelAuthentication
                            : null,
                        icon: const Icon(Icons.close),
                        label: const Text('取消登录'),
                      ),
                      TextButton.icon(
                        onPressed: _service.busy || _service.authPending
                            ? null
                            : () => _confirmLogout(context),
                        icon: const Icon(Icons.logout),
                        label: const Text('退出登录'),
                      ),
                    ],
                  ),
                  const Divider(height: 28),
                  Text('系统服务', style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 10,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _service.busy || _service.daemonActive
                            ? null
                            : _service.startDaemon,
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('启动 tailscaled'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _service.busy ||
                                _service.authPending ||
                                !_service.daemonActive
                            ? null
                            : () => _confirmStopDaemon(context),
                        icon: const Icon(Icons.stop),
                        label: const Text('停止 tailscaled'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoginAndLogs(
    BuildContext context, {
    required bool expandLogs,
  }) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_service.loginUrl.isNotEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                children: [
                  Text(
                    '扫描二维码完成登录',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 10),
                  Container(
                    color: Colors.white,
                    padding: const EdgeInsets.all(8),
                    child: QrImageView(
                      data: _service.loginUrl,
                      size: 152,
                      backgroundColor: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 10),
                  SelectableText(
                    _service.loginUrl,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: colors.primary),
                  ),
                ],
              ),
            ),
          ),
        if (_service.loginUrl.isNotEmpty) const SizedBox(height: 12),
        if (expandLogs)
          Expanded(child: _buildLogCard(context))
        else
          SizedBox(height: 240, child: _buildLogCard(context)),
      ],
    );
  }

  Widget _buildLogCard(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('运行日志', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Expanded(
              child: SelectionArea(
                child: ListView.builder(
                  itemCount: _service.logs.length,
                  itemBuilder: (context, index) => Text(
                    _service.logs[index],
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(fontFamily: 'monospace'),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 102, child: Text(label)),
          Expanded(
            child: SelectableText(value.isEmpty ? '—' : value),
          ),
        ],
      ),
    );
  }

  String get _statusText => switch (_service.backendState) {
        'Running' => '已连接',
        'NeedsLogin' => '需要登录',
        'Stopped' => '已断开',
        'Starting' => '正在连接',
        _ => _service.daemonActive ? '服务运行中' : '服务已停止',
      };

  Future<void> _confirmLogout(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('退出 Tailscale 登录？'),
        content: const Text('设备将从当前账号退出，重新使用时需要再次扫码登录。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('退出登录'),
          ),
        ],
      ),
    );
    if (confirmed == true) unawaited(_service.logout());
  }

  Future<void> _confirmStopDaemon(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('停止 tailscaled？'),
        content: const Text('停止系统服务会中断全部 Tailscale 连接。通常仅需使用“断开”。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('停止服务'),
          ),
        ],
      ),
    );
    if (confirmed == true) unawaited(_service.stopDaemon());
  }
}
