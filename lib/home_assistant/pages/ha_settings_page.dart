import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/remote_web_service.dart';
import '../../setting/remote_web_settings_page.dart';
import '../home_assistant_service.dart';

class HaSettingsPage extends StatefulWidget {
  const HaSettingsPage({super.key});

  @override
  State<HaSettingsPage> createState() => _HaSettingsPageState();
}

class _HaSettingsPageState extends State<HaSettingsPage> {
  static const String _interfaceKey = 'ha_management_interface';

  final _homeAssistant = HomeAssistantService.instance;
  final _remoteWeb = RemoteWebService.instance;
  String? _selectedInterface;

  @override
  void initState() {
    super.initState();
    _remoteWeb.addListener(_changed);
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    final prefs = await SharedPreferences.getInstance();
    await _remoteWeb.refreshAddresses();
    final saved = prefs.getString(_interfaceKey);
    if (!mounted) return;
    setState(() {
      _selectedInterface =
          _remoteWeb.networkAddresses.any((item) => item.name == saved)
              ? saved
              : _remoteWeb.networkAddresses.firstOrNull?.name;
    });
  }

  @override
  void dispose() {
    _remoteWeb.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _selectInterface(String? value) async {
    if (value == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_interfaceKey, value);
    if (mounted) setState(() => _selectedInterface = value);
  }

  String? get _managementUrl {
    final address = _remoteWeb.networkAddresses
        .where((item) => item.name == _selectedInterface)
        .firstOrNull
        ?.address
        .address;
    if (address == null) return null;
    final configured = Uri.tryParse(_homeAssistant.url);
    final scheme = configured?.scheme == 'https' ? 'https' : 'http';
    final port = configured?.hasPort == true
        ? configured!.port
        : scheme == 'https'
            ? 443
            : 8123;
    return Uri(scheme: scheme, host: address, port: port).toString();
  }

  @override
  Widget build(BuildContext context) {
    final url = _managementUrl;
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Home Assistant'),
        actions: [
          IconButton(
            tooltip: '刷新网卡',
            onPressed: _remoteWeb.refreshAddresses,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.admin_panel_settings_outlined),
              title: const Text('HA 地址与长期访问令牌'),
              subtitle: const Text('请通过远程 Web 设置输入，面板端不提供令牌输入框。'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const RemoteWebSettingsPage(),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '外部访问 HA 管理后台',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 6),
                  const Text('选择手机或电脑所在的网络，扫码打开 Home Assistant 管理页面。'),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    value: _selectedInterface,
                    decoration: const InputDecoration(
                      labelText: '访问网卡',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (final item in _remoteWeb.networkAddresses)
                        DropdownMenuItem(
                          value: item.name,
                          child: Text(item.label),
                        ),
                    ],
                    onChanged: _selectInterface,
                  ),
                  const SizedBox(height: 16),
                  if (url == null)
                    const Text('未找到可用的局域网 IPv4 地址')
                  else ...[
                    SelectableText(
                      url,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: colors.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: url));
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('HA 管理地址已复制')),
                        );
                      },
                      icon: const Icon(Icons.content_copy),
                      label: const Text('复制地址'),
                    ),
                    const SizedBox(height: 16),
                    Center(
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        color: Colors.white,
                        child: QrImageView(
                          data: url,
                          size: 210,
                          backgroundColor: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
