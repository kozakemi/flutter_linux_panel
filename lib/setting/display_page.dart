import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/display_service.dart';

class DisplaySettingsPage extends StatefulWidget {
  const DisplaySettingsPage({super.key});

  @override
  State<DisplaySettingsPage> createState() => _DisplaySettingsPageState();
}

class _DisplaySettingsPageState extends State<DisplaySettingsPage> {
  static const String _scaleFactorKey = 'display_scale_factor';

  // 4档缩放比例：100%, 125%, 150%, 175%, 200%
  static const List<double> _scaleValues = [1.0, 1.25, 1.50, 1.75, 2.0];
  static const List<String> _scaleLabels = [
    '100%',
    '125%',
    '150%',
    '175%',
    '200%'
  ];

  double _currentScale = 1.0;
  int _currentIndex = 0;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadScaleFactor();
  }

  /// 加载保存的缩放比例
  Future<void> _loadScaleFactor() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedScale = prefs.getDouble(_scaleFactorKey) ?? 1.0;

      // 找到最接近的档位
      int index = 0;
      double minDiff = double.infinity;
      for (int i = 0; i < _scaleValues.length; i++) {
        final diff = (savedScale - _scaleValues[i]).abs();
        if (diff < minDiff) {
          minDiff = diff;
          index = i;
        }
      }

      setState(() {
        _currentScale = _scaleValues[index];
        _currentIndex = index;
        _isLoading = false;
      });
    } catch (e) {
      print('加载缩放设置失败: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  /// 保存缩放比例
  Future<void> _saveScaleFactor(double scale) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_scaleFactorKey, scale);
      print('缩放设置已保存: $scale');
    } catch (e) {
      print('保存缩放设置失败: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('保存设置失败')),
        );
      }
    }
  }

  /// 更新缩放比例
  void _updateScale(int index) async {
    if (index >= 0 && index < _scaleValues.length) {
      final newScale = _scaleValues[index];
      setState(() {
        _currentScale = newScale;
        _currentIndex = index;
      });

      try {
        // 使用DisplayService更新全局缩放
        await DisplayService.instance.setScaleFactor(newScale);
        await _saveScaleFactor(newScale);

        // 显示提示信息
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('界面缩放已设置为 ${_scaleLabels[index]}'),
              duration: const Duration(milliseconds: 1200),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('设置失败: $e')),
          );
        }
      }
    }
  }

  /// 构建节标题
  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: Colors.grey,
        ),
      ),
    );
  }

  /// 构建预览区域
  Widget _buildPreviewSection() {
    return Transform.scale(
      scale: _currentScale,
      child: Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey[300]!),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '预览效果',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Icon(Icons.home, color: Colors.blue[600]),
                Icon(Icons.settings, color: Colors.grey[600]),
                Icon(Icons.wifi, color: Colors.green[600]),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              '这是界面缩放的预览效果',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('显示设置'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                _sectionHeader('界面缩放'),
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    children: [
                      ListTile(
                        title: const Text('缩放比例'),
                        subtitle: Text('当前: ${_scaleLabels[_currentIndex]}'),
                        trailing: Text(
                          _scaleLabels[_currentIndex],
                          style: TextStyle(
                            color: Theme.of(context).primaryColor,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        child: Column(
                          children: [
                            Slider(
                              value: _currentIndex.toDouble(),
                              min: 0,
                              max: (_scaleValues.length - 1).toDouble(),
                              divisions: _scaleValues.length - 1,
                              onChanged: (value) {
                                _updateScale(value.round());
                              },
                            ),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: _scaleLabels.map((label) {
                                return Text(
                                  label,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[600],
                                  ),
                                );
                              }).toList(),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                _sectionHeader('预览'),
                _buildPreviewSection(),
                Container(
                  margin: const EdgeInsets.all(16),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.blue[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue[200]!),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.info_outline,
                              color: Colors.blue[600], size: 20),
                          const SizedBox(width: 8),
                          Text(
                            '使用说明',
                            style: TextStyle(
                              fontWeight: FontWeight.w500,
                              color: Colors.blue[800],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '• 调整界面缩放比例以适应不同的屏幕尺寸\n'
                        '• 设置会自动保存并在下次启动时生效\n'
                        '• 建议根据屏幕大小选择合适的缩放比例',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.blue[700],
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
