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

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/display_service.dart';
import '../services/bluetooth_service.dart';
import '../models/bluetooth_models.dart';

class BluetoothSettingsPage extends StatefulWidget {
  const BluetoothSettingsPage({super.key});

  @override
  State<BluetoothSettingsPage> createState() => _BluetoothSettingsPageState();
}

class _BluetoothSettingsPageState extends State<BluetoothSettingsPage> {
  BluetoothService get _bluetoothService => BluetoothService.instance;

  BluetoothAdapterStatus _adapterStatus = BluetoothAdapterStatus.empty();
  List<BluetoothDevice> _devices = [];
  bool _isScanning = false;
  bool _hasAdapter = false; // 是否有蓝牙适配器

  StreamSubscription? _adapterStatusSubscription;
  StreamSubscription? _scanResultSubscription;
  StreamSubscription? _deviceUpdatedSubscription;

  Timer? _statusUpdateTimer;

  @override
  void initState() {
    super.initState();
    _setupService();
    _startStatusUpdateTimer();
  }

  @override
  void dispose() {
    _adapterStatusSubscription?.cancel();
    _scanResultSubscription?.cancel();
    _deviceUpdatedSubscription?.cancel();
    _statusUpdateTimer?.cancel();
    super.dispose();
  }

  /// 启动状态更新定时器
  void _startStatusUpdateTimer() {
    _statusUpdateTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      _refreshStatus();
    });
  }

  /// 初始化蓝牙服务
  Future<void> _setupService() async {
    try {
      if (!_bluetoothService.isInitialized) {
        await _bluetoothService.initialize();
      }

      // 检查是否有蓝牙适配器
      final adapterStatus = _bluetoothService.adapterStatus;
      final hasAdapter = adapterStatus.address.isNotEmpty;

      if (mounted) {
        setState(() {
          _hasAdapter = hasAdapter;
          _adapterStatus = adapterStatus;
        });
      }

      if (!hasAdapter) {
        // 没有蓝牙适配器，不需要继续设置监听
        return;
      }

      // 监听适配器状态
      _adapterStatusSubscription =
          _bluetoothService.adapterStatusStream.listen((status) {
        if (mounted) {
          setState(() {
            _adapterStatus = status;
            _isScanning = status.discovering;
            _hasAdapter = status.address.isNotEmpty;
          });
        }
      });

      // 监听扫描结果
      _scanResultSubscription =
          _bluetoothService.scanResultStream.listen((result) {
        if (mounted) {
          setState(() {
            _devices = result.devices;
          });
        }
      });

      // 监听设备更新
      _deviceUpdatedSubscription =
          _bluetoothService.deviceUpdatedStream.listen((device) {
        if (mounted) {
          setState(() {
            final index =
                _devices.indexWhere((d) => d.address == device.address);
            if (index >= 0) {
              _devices[index] = device;
            } else {
              _devices.add(device);
            }
          });
        }
      });

      // 获取当前状态
      _refreshStatus();
    } catch (e) {
      if (mounted) {
        setState(() {
          _hasAdapter = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('蓝牙服务初始化失败: $e')),
        );
      }
    }
  }

  /// 刷新状态
  void _refreshStatus() {
    if (!_bluetoothService.isInitialized) return;

    setState(() {
      _adapterStatus = _bluetoothService.adapterStatus;
      _devices = _bluetoothService.devices;
      _isScanning = _bluetoothService.isScanning;
    });
  }

  /// 开关蓝牙
  Future<void> _toggleBluetooth(bool value) async {
    try {
      final success = await _bluetoothService.togglePower(value);
      if (mounted) {
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(value ? '蓝牙已开启' : '蓝牙已关闭'),
              duration: const Duration(milliseconds: 1200),
            ),
          );
          if (value) {
            // 开启后自动扫描
            await Future.delayed(const Duration(milliseconds: 500));
            _startScan();
          }
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('操作失败')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('操作失败: $e')),
        );
      }
    }
  }

  /// 开始扫描
  Future<void> _startScan() async {
    if (!_adapterStatus.powered) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先开启蓝牙')),
      );
      return;
    }

    if (_isScanning) return;

    final success =
        await _bluetoothService.startScan(timeout: const Duration(seconds: 15));
    if (!success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('扫描启动失败')),
      );
    }
  }

  /// 停止扫描
  Future<void> _stopScan() async {
    await _bluetoothService.stopScan();
  }

  /// 配对设备
  Future<void> _pairDevice(BluetoothDevice device) async {
    if (device.paired) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${device.displayName} 已配对')),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('正在配对 ${device.displayName}...')),
    );

    final error = await _bluetoothService.pairDevice(device.address);
    if (mounted) {
      if (error == BluetoothError.ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${device.displayName} 配对成功')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('配对失败: ${error.message}')),
        );
      }
    }
  }

  /// 连接设备
  Future<void> _connectDevice(BluetoothDevice device) async {
    if (device.connected) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${device.displayName} 已连接')),
      );
      return;
    }

    // 如果未配对，先配对
    if (!device.paired) {
      await _pairDevice(device);
      // 等待配对完成
      await Future.delayed(const Duration(seconds: 1));
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('正在连接 ${device.displayName}...')),
    );

    final error = await _bluetoothService.connectDevice(device.address);
    if (mounted) {
      if (error == BluetoothError.ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${device.displayName} 已连接')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('连接失败: ${error.message}')),
        );
      }
    }
  }

  /// 断开设备
  Future<void> _disconnectDevice(BluetoothDevice device) async {
    final error = await _bluetoothService.disconnectDevice(device.address);
    if (mounted) {
      if (error == BluetoothError.ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${device.displayName} 已断开')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('断开失败: ${error.message}')),
        );
      }
    }
  }

  /// 取消配对
  Future<void> _unpairDevice(BluetoothDevice device) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('取消配对'),
        content: Text('确定要取消与 ${device.displayName} 的配对吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('确定'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final error = await _bluetoothService.unpairDevice(device.address);
    if (mounted) {
      if (error == BluetoothError.ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${device.displayName} 已取消配对')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('取消配对失败: ${error.message}')),
        );
      }
    }
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

  Widget _section(List<Widget> tiles) {
    if (tiles.isEmpty) return const SizedBox.shrink();

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: ListTile.divideTiles(
          context: context,
          tiles: tiles,
          color: Theme.of(context).dividerColor.withOpacity(0.1),
        ).toList(),
      ),
    );
  }

  Widget _bluetoothIcon() {
    return Icon(
      Icons.bluetooth,
      size: 48,
      color: _adapterStatus.powered
          ? Theme.of(context).colorScheme.onSurface
          : Colors.grey,
    );
  }

  IconData _getDeviceIcon(BluetoothDevice device) {
    switch (device.deviceType) {
      case BluetoothDeviceType.phone:
        return Icons.phone_android;
      case BluetoothDeviceType.computer:
        return Icons.computer;
      case BluetoothDeviceType.audioVideo:
        return Icons.headphones;
      case BluetoothDeviceType.peripheral:
        return Icons.keyboard;
      case BluetoothDeviceType.imaging:
        return Icons.print;
      case BluetoothDeviceType.wearable:
        return Icons.watch;
      case BluetoothDeviceType.toy:
        return Icons.toys;
      case BluetoothDeviceType.health:
        return Icons.favorite;
      default:
        return Icons.bluetooth;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scale = DisplayService.instance.scaleFactor;
    final iconSize = 24.0 * scale;
    final toolbarHeight = 56.0 * scale;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('蓝牙'),
        toolbarHeight: toolbarHeight,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          iconSize: iconSize,
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          if (_hasAdapter && _adapterStatus.powered)
            IconButton(
              icon: Icon(_isScanning ? Icons.stop : Icons.refresh),
              iconSize: iconSize,
              onPressed: _isScanning ? _stopScan : _startScan,
              tooltip: _isScanning ? '停止扫描' : '刷新设备',
            ),
        ],
      ),
      body: ListView(
        children: [
          // 顶部说明卡片
          Card(
            margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _bluetoothIcon(),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '蓝牙',
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '连接蓝牙设备，如耳机、键盘、鼠标等外设',
                          style: TextStyle(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          // 没有蓝牙适配器时显示提示
          if (!_hasAdapter) ...[
            Padding(
              padding: const EdgeInsets.all(32),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.bluetooth_disabled,
                        size: 64, color: Colors.grey.shade400),
                    const SizedBox(height: 16),
                    Text(
                      '未检测到蓝牙适配器',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '请检查设备是否支持蓝牙，或尝试连接 USB 蓝牙适配器',
                      style: TextStyle(color: Colors.grey.shade600),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ] else ...[
            // 开关行
            _section([
              ListTile(
                title: const Text('蓝牙'),
                trailing: Switch(
                  value: _adapterStatus.powered,
                  onChanged: (v) => _toggleBluetooth(v),
                ),
              ),
            ]),

            const SizedBox(height: 24),

            // 已连接的设备
            if (_adapterStatus.powered) ...[
              // 已连接
              if (_devices.any((d) => d.connected)) ...[
                _sectionHeader('已连接'),
                _section(
                  _devices
                      .where((d) => d.connected)
                      .map((device) => _buildDeviceTile(device))
                      .toList(),
                ),
                const SizedBox(height: 24),
              ],

              // 已配对但未连接的设备
              if (_devices.any((d) => d.paired && !d.connected)) ...[
                _sectionHeader('我的设备'),
                _section(
                  _devices
                      .where((d) => d.paired && !d.connected)
                      .map((device) => _buildDeviceTile(device))
                      .toList(),
                ),
                const SizedBox(height: 24),
              ],

              // 可用设备标题
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Row(
                  children: [
                    Text(
                      '可用设备',
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (_isScanning) ...[
                      const SizedBox(width: 8),
                      const SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '扫描中...',
                        style: TextStyle(
                          color: Colors.grey.shade500,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              // 可用设备列表（未配对的设备）
              if (_devices.any((d) => !d.paired))
                _section(
                  _devices
                      .where((d) => !d.paired)
                      .map((device) => _buildDeviceTile(device))
                      .toList(),
                )
              else if (_isScanning)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator()),
                )
              else
                Padding(
                  padding: const EdgeInsets.all(32),
                  child: Center(
                    child: Column(
                      children: [
                        Icon(Icons.bluetooth_searching,
                            size: 48, color: Colors.grey.shade400),
                        const SizedBox(height: 16),
                        Text(
                          '未发现可用设备',
                          style: TextStyle(color: Colors.grey.shade600),
                        ),
                        const SizedBox(height: 8),
                        ElevatedButton.icon(
                          onPressed: _startScan,
                          icon: const Icon(Icons.refresh),
                          label: const Text('开始扫描'),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ], // else _hasAdapter
        ],
      ),
    );
  }

  /// 构建设备列表项
  Widget _buildDeviceTile(BluetoothDevice device) {
    String subtitle;
    if (device.connected) {
      subtitle = '已连接';
    } else if (device.paired) {
      subtitle = '已配对';
    } else {
      subtitle = '信号强度: ${device.signalPercentage}%';
    }

    return ListTile(
      leading: Icon(
        _getDeviceIcon(device),
        color:
            device.connected ? Theme.of(context).colorScheme.onSurface : null,
      ),
      title: Text(device.displayName),
      subtitle: Text(subtitle),
      trailing: device.connected
          ? Icon(Icons.check, color: Theme.of(context).colorScheme.onSurface)
          : const Icon(Icons.chevron_right, size: 20),
      onTap: () {
        if (device.connected) {
          _showDeviceOptions(device);
        } else {
          _connectDevice(device);
        }
      },
      onLongPress: () {
        HapticFeedback.lightImpact();
        _showDeviceOptions(device);
      },
    );
  }

  /// 显示设备选项
  void _showDeviceOptions(BluetoothDevice device) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(_getDeviceIcon(device)),
              title: Text(device.displayName),
              subtitle: Text(device.address),
            ),
            const Divider(),
            if (device.connected)
              ListTile(
                leading: const Icon(Icons.bluetooth_disabled),
                title: const Text('断开连接'),
                onTap: () {
                  Navigator.of(context).pop();
                  _disconnectDevice(device);
                },
              )
            else
              ListTile(
                leading: const Icon(Icons.bluetooth_connected),
                title: const Text('连接'),
                onTap: () {
                  Navigator.of(context).pop();
                  _connectDevice(device);
                },
              ),
            if (device.paired)
              ListTile(
                leading: const Icon(Icons.link_off),
                title: const Text('取消配对'),
                onTap: () {
                  Navigator.of(context).pop();
                  _unpairDevice(device);
                },
              ),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('设备详情'),
              onTap: () {
                Navigator.of(context).pop();
                _showDeviceDetails(device);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  /// 显示设备详情
  void _showDeviceDetails(BluetoothDevice device) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(
              _getDeviceIcon(device),
              color: Theme.of(context).colorScheme.onSurface,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                device.displayName,
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildDetailRow('名称', device.name.isEmpty ? '未知' : device.name),
              const SizedBox(height: 12),
              _buildDetailRow('别名', device.alias.isEmpty ? '未知' : device.alias),
              const SizedBox(height: 12),
              _buildDetailRow('地址', device.address),
              const SizedBox(height: 12),
              _buildDetailRow('类型', _deviceTypeName(device.deviceType)),
              const SizedBox(height: 12),
              _buildDetailRow(
                  '信号强度', '${device.rssi} dBm (${device.signalPercentage}%)'),
              const SizedBox(height: 12),
              _buildDetailRow('配对状态', device.paired ? '已配对' : '未配对'),
              const SizedBox(height: 12),
              _buildDetailRow('连接状态', device.connected ? '已连接' : '未连接'),
              const SizedBox(height: 12),
              _buildDetailRow('信任状态', device.trusted ? '已信任' : '未信任'),
              const SizedBox(height: 12),
              _buildDetailRow('BLE 设备', device.isBleDevice ? '是' : '否'),
              if (device.uuids.isNotEmpty) ...[
                const SizedBox(height: 12),
                _buildDetailRow('服务 UUID', '${device.uuids.length} 个'),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('关闭'),
          ),
          if (!device.connected)
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                _connectDevice(device);
              },
              child: const Text('连接'),
            ),
        ],
      ),
    );
  }

  String _deviceTypeName(BluetoothDeviceType type) {
    switch (type) {
      case BluetoothDeviceType.phone:
        return '手机';
      case BluetoothDeviceType.computer:
        return '电脑';
      case BluetoothDeviceType.audioVideo:
        return '音频/视频设备';
      case BluetoothDeviceType.peripheral:
        return '外设';
      case BluetoothDeviceType.imaging:
        return '图像设备';
      case BluetoothDeviceType.wearable:
        return '可穿戴设备';
      case BluetoothDeviceType.toy:
        return '玩具';
      case BluetoothDeviceType.health:
        return '健康设备';
      default:
        return '未知设备';
    }
  }

  Widget _buildDetailRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 80,
          child: Text(
            label,
            style: TextStyle(
              color: Colors.grey.shade600,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w400,
            ),
          ),
        ),
      ],
    );
  }
}
