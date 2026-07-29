import 'dart:io';

import 'package:flutter/material.dart';

import '../launchpad/file_manager_page.dart';
import '../services/display_service.dart';
import '../services/theme_service.dart';
import '../services/wallpaper_service.dart';

class WallpaperSettingsPage extends StatefulWidget {
  const WallpaperSettingsPage({super.key});

  @override
  State<WallpaperSettingsPage> createState() => _WallpaperSettingsPageState();
}

class _WallpaperSettingsPageState extends State<WallpaperSettingsPage> {
  static const List<Color> _presetColors = <Color>[
    Color(0xff1976d2),
    Color(0xff00695c),
    Color(0xff2e7d32),
    Color(0xff558b2f),
    Color(0xfff57f17),
    Color(0xffef6c00),
    Color(0xffc62828),
    Color(0xffad1457),
    Color(0xff7b1fa2),
    Color(0xff512da8),
    Color(0xff3949ab),
    Color(0xff455a64),
  ];

  final WallpaperService _wallpaperService = WallpaperService.instance;
  final ThemeService _themeService = ThemeService.instance;
  bool _busy = false;

  Future<void> _chooseWallpaper() async {
    final path = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => const FileManagerPage(pickImage: true),
      ),
    );
    if (path == null || !mounted) return;
    await _setWallpaper(path);
  }

  Future<void> _setWallpaper(String path) async {
    setState(() => _busy = true);
    try {
      await _wallpaperService.setWallpaper(path);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('壁纸已更新')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('设置壁纸失败：$error')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _useWallpaperColor() async {
    final path = _wallpaperService.wallpaperPath;
    if (path == null) return;
    setState(() => _busy = true);
    try {
      await _themeService.useWallpaperSeedColor(path);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('提取主题色失败：$error')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showCustomColorDialog() async {
    final current = _themeService.seedColor;
    double red = current.r * 255;
    double green = current.g * 255;
    double blue = current.b * 255;
    final selected = await showDialog<Color>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final preview = Color.fromARGB(
            255,
            red.round(),
            green.round(),
            blue.round(),
          );
          Widget slider(String label, double value, ValueChanged<double> set) {
            return Row(
              children: [
                SizedBox(width: 24, child: Text(label)),
                Expanded(
                  child: Slider(
                    min: 0,
                    max: 255,
                    value: value,
                    onChanged: (newValue) =>
                        setDialogState(() => set(newValue)),
                  ),
                ),
                SizedBox(width: 36, child: Text('${value.round()}')),
              ],
            );
          }

          return AlertDialog(
            title: const Text('自定义主题色'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  height: 56,
                  decoration: BoxDecoration(
                    color: preview,
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                const SizedBox(height: 12),
                slider('R', red, (value) => red = value),
                slider('G', green, (value) => green = value),
                slider('B', blue, (value) => blue = value),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, preview),
                child: const Text('应用'),
              ),
            ],
          );
        },
      ),
    );
    if (selected != null) {
      await _themeService.setSeedColor(selected);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scale = DisplayService.instance.scaleFactor;
    return Scaffold(
      appBar: AppBar(
        title: const Text('壁纸和主题色'),
        toolbarHeight: 56 * scale,
      ),
      body: ListenableBuilder(
        listenable: Listenable.merge([_wallpaperService, _themeService]),
        builder: (context, child) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('壁纸', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            AspectRatio(
              aspectRatio: 16 / 9,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: _wallpaperService.wallpaperPath == null
                    ? Image.asset(
                        WallpaperService.defaultAssetPath,
                        fit: BoxFit.cover,
                      )
                    : Image.file(
                        File(_wallpaperService.wallpaperPath!),
                        fit: BoxFit.cover,
                      ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                FilledButton.icon(
                  onPressed: _busy ? null : _chooseWallpaper,
                  icon: const Icon(Icons.folder_open),
                  label: const Text('从文件管理器选择'),
                ),
                const SizedBox(width: 12),
                OutlinedButton(
                  onPressed: _busy || !_wallpaperService.hasCustomWallpaper
                      ? null
                      : _wallpaperService.resetWallpaper,
                  child: const Text('恢复默认'),
                ),
              ],
            ),
            const SizedBox(height: 28),
            Text('Material 主题色',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Card(
              child: SwitchListTile(
                secondary: Icon(
                  Icons.auto_awesome,
                  color: _themeService.seedColor,
                ),
                title: const Text('从壁纸提取主题色'),
                subtitle: const Text('根据壁纸主色生成 Material 3 配色'),
                value: _themeService.useWallpaperColor,
                onChanged: _busy || !_wallpaperService.hasCustomWallpaper
                    ? null
                    : (enabled) {
                        if (enabled) {
                          _useWallpaperColor();
                        } else {
                          _themeService.setSeedColor(
                            _themeService.seedColor,
                          );
                        }
                      },
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final color in _presetColors)
                  InkWell(
                    onTap:
                        _busy ? null : () => _themeService.setSeedColor(color),
                    borderRadius: BorderRadius.circular(24),
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: color,
                        border: Border.all(
                          color: _themeService.seedColor.toARGB32() ==
                                      color.toARGB32() &&
                                  !_themeService.useWallpaperColor
                              ? Theme.of(context).colorScheme.onSurface
                              : Colors.transparent,
                          width: 3,
                        ),
                      ),
                    ),
                  ),
                ActionChip(
                  avatar: const Icon(Icons.colorize),
                  label: const Text('自定义'),
                  onPressed: _busy ? null : _showCustomColorDialog,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
