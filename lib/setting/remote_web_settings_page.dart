import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../services/display_service.dart';
import '../services/remote_web_service.dart';

class RemoteWebSettingsPage extends StatefulWidget {
  const RemoteWebSettingsPage({super.key});

  @override
  State<RemoteWebSettingsPage> createState() => _RemoteWebSettingsPageState();
}

class _RemoteWebSettingsPageState extends State<RemoteWebSettingsPage> {
  final RemoteWebService _service = RemoteWebService.instance;

  @override
  void initState() {
    super.initState();
    _service.addListener(_handleServiceChanged);
    _service.refreshAddresses();
  }

  @override
  void dispose() {
    _service.removeListener(_handleServiceChanged);
    super.dispose();
  }

  void _handleServiceChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _setEnabled(bool enabled) async {
    await _service.setEnabled(enabled);
    if (!mounted || _service.error == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(_service.error!)),
    );
  }

  Future<void> _copyLink() async {
    final url = _service.primaryUrl;
    if (url == null) return;
    await Clipboard.setData(ClipboardData(text: url));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('访问链接已复制')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scale = DisplayService.instance.scaleFactor;
    final url = _service.primaryUrl;
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('远程 Web 设置'),
        toolbarHeight: 56 * scale,
        actions: [
          IconButton(
            tooltip: '刷新网络地址',
            onPressed: _service.refreshAddresses,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: SwitchListTile(
              secondary: const Icon(Icons.language),
              title: const Text('启用远程 Web 设置'),
              subtitle: const Text('允许同一局域网中的手机或电脑设置壁纸和天气'),
              value: _service.enabled,
              onChanged: _service.starting ? null : _setEnabled,
            ),
          ),
          if (_service.starting) ...[
            const SizedBox(height: 20),
            const Center(child: CircularProgressIndicator()),
          ],
          if (_service.enabled) ...[
            const SizedBox(height: 16),
            Card(
              child: ListTile(
                leading: const Icon(Icons.settings_ethernet),
                title: const Text('Web 访问网卡'),
                subtitle: DropdownButton<String?>(
                  value: _service.selectedInterface,
                  isExpanded: true,
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('自动（所有网卡）'),
                    ),
                    for (final item in _service.networkAddresses)
                      DropdownMenuItem<String?>(
                        value: item.name,
                        child: Text(item.label),
                      ),
                  ],
                  onChanged: _service.starting
                      ? null
                      : (value) => _service.setInterface(value),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '访问地址',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    if (url == null)
                      const Text('未找到可用的局域网 IPv4 地址')
                    else ...[
                      SelectableText(
                        url,
                        style: TextStyle(
                          color: colorScheme.primary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: _copyLink,
                        icon: const Icon(Icons.content_copy),
                        label: const Text('复制链接'),
                      ),
                      const SizedBox(height: 24),
                      Center(
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          color: Colors.white,
                          child: QrImageView(
                            data: url,
                            version: QrVersions.auto,
                            size: 220,
                            backgroundColor: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        '使用手机相机扫描二维码，或在同一局域网的浏览器中打开链接。',
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              color: colorScheme.secondaryContainer,
              child: ListTile(
                leading: Icon(
                  Icons.security,
                  color: colorScheme.onSecondaryContainer,
                ),
                title: Text(
                  '链接包含本次服务的 4 位访问令牌',
                  style: TextStyle(color: colorScheme.onSecondaryContainer),
                ),
                subtitle: Text(
                  '关闭并重新开启服务后，旧链接会自动失效。',
                  style: TextStyle(color: colorScheme.onSecondaryContainer),
                ),
              ),
            ),
          ],
          if (_service.error != null) ...[
            const SizedBox(height: 12),
            Text(
              _service.error!,
              style: TextStyle(color: colorScheme.error),
            ),
          ],
        ],
      ),
    );
  }
}
