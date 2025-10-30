import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'setting/wifi_page.dart';

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

  Widget _icon(String assetPath) {
    return SvgPicture.asset(
      assetPath,
      width: 24,
      height: 24,
      fit: BoxFit.scaleDown,
    );
  }

  Widget _section(List<Widget> tiles) {
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
    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F7), // iOS 风格的分组背景
      appBar: AppBar(
        title: const Text('设置'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: ListView(
        children: [
          _sectionHeader('网络与连接'),
          _section([
            ListTile(
              leading: _icon('source/app_ico/WLAN.svg'),
              title: const Text('Wi‑Fi'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const WiFiSettingsPage()),
              ),
            ),
            ListTile(
              leading: _icon('source/app_ico/Bluetooth.svg'),
              title: const Text('蓝牙'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _showNotImplemented('蓝牙'),
            ),
          ]),
          const SizedBox(height: 24),
          _sectionHeader('显示与声音'),
          _section([
            ListTile(
              leading: _icon('source/app_ico/DisplayBrightness.svg'),
              title: const Text('显示设置'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _showNotImplemented('显示设置'),
            ),
            ListTile(
              leading: _icon('source/app_ico/SoundsHaptics.svg'),
              title: const Text('声音设置'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _showNotImplemented('声音设置'),
            ),
            ListTile(
              leading: _icon('source/app_ico/Wallpaper.svg'),
              title: const Text('壁纸设置'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _showNotImplemented('壁纸设置'),
            ),
          ]),
          const SizedBox(height: 24),
          _sectionHeader('系统与输入'),
          _section([
            ListTile(
              leading: _icon('source/app_ico/Battery.svg'),
              title: const Text('电池管理'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _showNotImplemented('电池管理'),
            ),
            ListTile(
              leading: _icon('source/app_ico/Keyboards.svg'),
              title: const Text('键盘设置'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _showNotImplemented('键盘设置'),
            ),
          ]),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
