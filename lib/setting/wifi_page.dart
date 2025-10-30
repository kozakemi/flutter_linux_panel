import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:virtual_keyboard_multi_language/virtual_keyboard_multi_language.dart';

import '../models/wifi_models.dart';
import '../services/wifi_websocket_service.dart';
import '../services/websocket_client.dart';

class WiFiSettingsPage extends StatefulWidget {
  const WiFiSettingsPage({super.key});

  @override
  State<WiFiSettingsPage> createState() => _WiFiSettingsPageState();
}

class _WiFiSettingsPageState extends State<WiFiSettingsPage> {
  final WiFiWebSocketService _wifiService = WiFiWebSocketService.instance;
  
  WiFiStatus _wifiStatus = const WiFiStatus(enabled: false, connected: false);
  WiFiScanResult _scanResult = const WiFiScanResult(networks: []);
  WebSocketConnectionState _connectionState = WebSocketConnectionState.disconnected;
  
  bool _isScanning = false;
  bool _isConnecting = false;
  
  StreamSubscription? _statusSubscription;
  StreamSubscription? _scanSubscription;
  StreamSubscription? _connectionEventSubscription;
  StreamSubscription? _connectionStateSubscription;

  @override
  void initState() {
    super.initState();
    _initializeService();
  }

  @override
  void dispose() {
    _statusSubscription?.cancel();
    _scanSubscription?.cancel();
    _connectionEventSubscription?.cancel();
    _connectionStateSubscription?.cancel();
    super.dispose();
  }

  /// 初始化 WebSocket 服务
  Future<void> _initializeService() async {
    try {
      await _wifiService.initialize();
      
      // 监听状态变化
      _statusSubscription = _wifiService.statusStream.listen((status) {
        if (mounted) {
          setState(() {
            _wifiStatus = status;
          });
        }
      });
      
      // 监听扫描结果
      _scanSubscription = _wifiService.scanStream.listen((scanResult) {
        if (mounted) {
          setState(() {
            _scanResult = scanResult;
            _isScanning = false;
          });
        }
      });
      
      // 监听连接事件
      _connectionEventSubscription = _wifiService.connectionEventStream.listen((message) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(message)),
          );
        }
      });
      
      // 监听 WebSocket 连接状态
      _connectionStateSubscription = _wifiService.connectionStateStream.listen((state) {
        if (mounted) {
          setState(() {
            _connectionState = state;
          });
        }
      });
      
      // 初始扫描
      await _loadStatusAndScan();
      
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('连接服务器失败: $e')),
        );
      }
    }
  }

  /// 加载状态并扫描网络
  Future<void> _loadStatusAndScan() async {
    setState(() {
      _isScanning = true;
    });
    
    // 刷新状态
    final statusError = await _wifiService.refreshStatus();
    if (statusError != WiFiError.ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('获取状态失败: ${statusError.message}')),
      );
    }
    
    // 扫描网络
    final scanError = await _wifiService.scanNetworks();
    if (scanError != WiFiError.ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('扫描网络失败: ${scanError.message}')),
      );
      setState(() {
        _isScanning = false;
      });
    }
  }

  /// 开关 Wi-Fi
  Future<void> _toggleWifi(bool value) async {
    final error = await _wifiService.enableWiFi(value);
    
    if (mounted) {
      if (error == WiFiError.ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(value ? 'Wi-Fi 已开启' : 'Wi-Fi 已关闭'),
            duration: const Duration(milliseconds: 1200),
          ),
        );
        if (value) {
          await _loadStatusAndScan();
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('操作失败: ${error.message}')),
        );
      }
    }
  }

  /// 连接到 Wi-Fi 网络
  Future<void> _connectFlow(String ssid) async {
    // 检查是否已连接到该网络
    if (_wifiService.isConnectedTo(ssid)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已连接到 $ssid')),
      );
      return;
    }

    // 检查网络是否需要密码
    final requiresPassword = _wifiService.networkRequiresPassword(ssid);
    
    if (!requiresPassword) {
      // 直接连接无密码网络
      await _connectToNetwork(ssid, '');
      return;
    }

    // 显示密码输入对话框
    final TextEditingController pwdController = TextEditingController();
    final FocusNode pwdFocusNode = FocusNode();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        String inputPassword = '';
        bool connecting = false;

        WidgetsBinding.instance.addPostFrameCallback((_) {
          pwdFocusNode.requestFocus();
        });

        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            Future<void> submit() async {
              if (inputPassword.isEmpty) {
                ScaffoldMessenger.of(context)
                    .showSnackBar(const SnackBar(content: Text('请输入密码')));
                return;
              }
              
              setModalState(() {
                connecting = true;
              });

              // 连接网络
              final error = await _wifiService.connectToNetwork(
                ssid: ssid,
                password: inputPassword,
              );

              // 弹窗可能已经关闭，检查 context 是否有效
              if (!ctx.mounted) return;

              if (error == WiFiError.ok) {
                Navigator.of(ctx).pop();
                ScaffoldMessenger.of(context)
                    .showSnackBar(SnackBar(content: Text('已连接到 $ssid')));
              } else {
                setModalState(() {
                  connecting = false;
                });
                ScaffoldMessenger.of(context)
                    .showSnackBar(SnackBar(content: Text('连接失败: ${error.message}')));
              }
            }

            const keyboardHeight = 300.0;
            return Padding(
              padding:
                  EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
              child: SafeArea(
                child: AnimatedSize(
                  duration: const Duration(milliseconds: 200),
                  child: Container(
                    color: Colors.white,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                          child: Row(
                            children: [
                              Expanded(
                                  child: Text('连接到 $ssid',
                                      style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600))),
                              IconButton(
                                icon: const Icon(Icons.close),
                                onPressed: () => Navigator.of(ctx).pop(),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: TextField(
                            readOnly: true,
                            autofocus: true,
                            showCursor: true,
                            enableInteractiveSelection: false,
                            focusNode: pwdFocusNode,
                            onTapOutside: (_) => pwdFocusNode.requestFocus(),
                            decoration: const InputDecoration(
                              labelText: '密码',
                              hintText: '请输入网络密码',
                              border: OutlineInputBorder(),
                            ),
                            controller: pwdController,
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          height: keyboardHeight,
                          child: Container(
                            color: const Color(0xFF222222),
                            child: Focus(
                              canRequestFocus: false,
                              skipTraversal: true,
                              child: VirtualKeyboard(
                                height: keyboardHeight,
                                textColor: Colors.white,
                                defaultLayouts: const [
                                  VirtualKeyboardDefaultLayouts.English,
                                ],
                                type: VirtualKeyboardType.Alphanumeric,
                                postKeyPress: (key) {
                                  setModalState(() {
                                    switch (key.keyType) {
                                      case VirtualKeyboardKeyType.String:
                                        inputPassword += key.text ?? '';
                                        break;
                                      case VirtualKeyboardKeyType.Action:
                                        final action = key.action;
                                        if (action == null) break;
                                        switch (action) {
                                          case VirtualKeyboardKeyAction
                                                .Backspace:
                                            if (inputPassword.isNotEmpty) {
                                              inputPassword =
                                                  inputPassword.substring(0,
                                                      inputPassword.length - 1);
                                            }
                                            break;
                                          case VirtualKeyboardKeyAction.Space:
                                            inputPassword += ' ';
                                            break;
                                          case VirtualKeyboardKeyAction.Return:
                                            if (connecting) break;
                                            submit();
                                            break;
                                          case VirtualKeyboardKeyAction.Shift:
                                            break;
                                          default:
                                            break;
                                        }
                                        break;
                                    }
                                    pwdController.text = inputPassword;
                                    pwdFocusNode.requestFocus();
                                  });
                                },
                              ),
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                          child: Row(
                            children: [
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: connecting ? null : submit,
                                  icon: connecting
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2))
                                      : const Icon(Icons.wifi),
                                  label: const Text('连接'),
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
          },
        );
      },
    ).whenComplete(() {
      pwdController.dispose();
      pwdFocusNode.dispose();
    });
  }

  /// 连接到网络的辅助方法
  Future<void> _connectToNetwork(String ssid, String password) async {
    setState(() {
      _isConnecting = true;
    });

    final error = await _wifiService.connectToNetwork(
      ssid: ssid,
      password: password,
    );

    setState(() {
      _isConnecting = false;
    });

    if (error == WiFiError.ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已连接到 $ssid')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('连接失败: ${error.message}')),
      );
    }
  }

  /// 断开当前网络连接
  Future<void> _disconnectFromNetwork() async {
    if (!_wifiStatus.connected) return;

    setState(() {
      _isConnecting = true;
    });

    final error = await _wifiService.disconnectFromNetwork();

    setState(() {
      _isConnecting = false;
    });

    if (error == WiFiError.ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已断开连接')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('断开连接失败: ${error.message}')),
      );
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

  Widget _wifiIcon() {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: const Color(0xFFEAF3FF),
        borderRadius: BorderRadius.circular(12),
      ),
      alignment: Alignment.center,
      child: SvgPicture.asset(
        'source/app_ico/WLAN.svg',
        width: 28,
        height: 28,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F7),
      appBar: AppBar(
        title: const Text('无线局域网'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isScanning ? null : _loadStatusAndScan,
            tooltip: '刷新网络',
          ),
          if (_wifiStatus.connected)
            IconButton(
              icon: const Icon(Icons.wifi_off),
              onPressed: (_isConnecting) ? null : _disconnectFromNetwork,
              tooltip: '断开连接',
            ),
        ],
      ),
      body: ListView(
        children: [
          // 顶部说明卡片
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Material(
              color: Colors.white,
              surfaceTintColor: Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              clipBehavior: Clip.antiAlias,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _wifiIcon(),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '无线局域网',
                            style: TextStyle(
                                fontSize: 18, fontWeight: FontWeight.w600),
                          ),
                          SizedBox(height: 6),
                          Text(
                            '接入无线局域网，查看可用网络，并管理加入网络及附近热点设置',
                            style:
                                TextStyle(color: Colors.black54, height: 1.35),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(height: 12),

          // 开关行
          _section([
            ListTile(
              title: const Text('无线局域网'),
              trailing: Switch(
                value: _wifiStatus.enabled,
                onChanged: (v) => _toggleWifi(v),
              ),
            ),
          ]),

          const SizedBox(height: 24),

          // 当前连接网络
          if (_wifiStatus.connected && _wifiStatus.currentNetwork != null) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                '已连接',
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            _section([
              ListTile(
                leading: const Icon(Icons.check, color: Colors.blue),
                title: Text(_wifiStatus.currentNetwork!.ssid),
                subtitle: const Text('已连接'),
                trailing: const Wrap(
                  spacing: 12,
                  children: [
                    Icon(Icons.lock_outline, size: 20, color: Colors.black54),
                    Icon(Icons.info_outline, size: 20, color: Colors.black54),
                  ],
                ),
                onTap: () {},
              ),
            ]),
            const SizedBox(height: 24),
          ],

          if (_wifiStatus.enabled && _scanResult.networks.isNotEmpty) ...[
            _sectionHeader('可用网络'),
            if (_isScanning)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              )
            else
              _section(
                _scanResult.networks
                    .map(
                      (network) => ListTile(
                        title: Text(network.ssid),
                        subtitle: Text('信号强度: ${network.signalPercentage}%'),
                        trailing: Wrap(
                          spacing: 12,
                          children: [
                            if (network.isSecured)
                              const Icon(Icons.lock_outline,
                                  size: 20, color: Colors.black54),
                            const Icon(Icons.info_outline,
                                size: 20, color: Colors.black54),
                          ],
                        ),
                        onTap: () => _connectFlow(network.ssid),
                      ),
                    )
                    .toList(),
              ),
          ],
        ],
      ),
    );
  }
}
