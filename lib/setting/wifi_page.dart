import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:virtual_keyboard_multi_language/virtual_keyboard_multi_language.dart';

class WiFiSettingsPage extends StatefulWidget {
  const WiFiSettingsPage({super.key});

  @override
  State<WiFiSettingsPage> createState() => _WiFiSettingsPageState();
}

class _WiFiSettingsPageState extends State<WiFiSettingsPage> {
  bool wifiEnabled = true;
  String? connectedSsid;

  final List<String> myNetworks = [];

  final List<String> otherNetworks = [];

  @override
  void initState() {
    super.initState();
    _loadStatusAndScan();
  }

  Future<void> _loadStatusAndScan() async {
    final list = await _mockScan();
    setState(() {
      myNetworks.clear();
      otherNetworks.clear();
      for (final ap in list) {
        final ssid = ap['ssid'] as String? ?? '';
        if (ssid.isEmpty) continue;
        if (ssid == connectedSsid) continue;
        if (ssid.startsWith('CMCC')) {
          myNetworks.add(ssid);
        } else {
          otherNetworks.add(ssid);
        }
      }
    });
  }

  Future<List<Map<String, dynamic>>> _mockScan() async {
    await Future.delayed(const Duration(milliseconds: 150));
    return const [];
  }

  Future<void> _toggleWifi(bool value) async {
    setState(() => wifiEnabled = value);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(value ? 'Wi‑Fi 已开启（模拟）' : 'Wi‑Fi 已关闭（模拟）'),
        duration: const Duration(milliseconds: 1200),
      ),
    );
    await _loadStatusAndScan();
  }

  Future<void> _connectFlow(String ssid) async {
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
              await Future.delayed(const Duration(milliseconds: 500));
              final ok = inputPassword.isNotEmpty;

              // 弹窗可能已经关闭，检查 context 是否有效
              if (!ctx.mounted) return;

              if (ok) {
                Navigator.of(ctx).pop();
                setState(() {
                  connectedSsid = ssid;
                });
                ScaffoldMessenger.of(context)
                    .showSnackBar(SnackBar(content: Text('已连接到 $ssid（模拟）')));
                await _loadStatusAndScan();
              } else {
                setModalState(() {
                  connecting = false;
                });
                ScaffoldMessenger.of(context)
                    .showSnackBar(const SnackBar(content: Text('连接失败，请输入密码')));
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
            onPressed: _loadStatusAndScan,
            tooltip: '刷新网络',
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
                value: wifiEnabled,
                onChanged: (v) => _toggleWifi(v),
              ),
            ),
          ]),

          const SizedBox(height: 24),

          // 当前连接网络
          if (connectedSsid != null) ...[
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
                title: Text(connectedSsid!),
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

          _sectionHeader('我的网络'),
          _section(
            myNetworks
                .map(
                  (ssid) => ListTile(
                    title: Text(ssid),
                    trailing: const Icon(Icons.info_outline,
                        size: 20, color: Colors.black54),
                    onTap: () => _connectFlow(ssid),
                  ),
                )
                .toList(),
          ),

          const SizedBox(height: 24),

          _sectionHeader('其他网络'),
          _section(
            otherNetworks
                .map(
                  (ssid) => ListTile(
                    title: Text(ssid),
                    trailing: const Wrap(
                      spacing: 12,
                      children: [
                        Icon(Icons.lock_outline,
                            size: 20, color: Colors.black54),
                        Icon(Icons.info_outline,
                            size: 20, color: Colors.black54),
                      ],
                    ),
                    onTap: () => _connectFlow(ssid),
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }
}
