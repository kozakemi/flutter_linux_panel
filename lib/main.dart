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

import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:intl/intl.dart';
import 'settings_page.dart';
import 'calendar_page.dart';
import 'launchpad_page.dart';
import 'loading_page.dart';
import 'global_tap_ripple.dart';
import 'services/display_service.dart';
import 'services/websocket_service_manager.dart';
import 'services/wifi_module.dart';
import 'models/wifi_models.dart';

// 全局配置变量
const bool showSeconds = true; // 控制是否显示秒

// 使用相对比例而不是固定尺寸
const double sidePanelWidthRatio = 0.2; // 侧边栏宽度占屏幕宽度的比例

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 初始化显示服务
  await DisplayService.instance.initialize();

  // 初始化 WebSocket 服务（在应用启动阶段）
  try {
    await WebSocketServiceManager.instance.initialize();
  } catch (_) {
    // 允许离线模式继续运行
  }

  // debugRepaintRainbowEnabled = true;
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: DisplayService.instance,
      builder: (context, child) {
        return MaterialApp(
          title: 'Anime Clock',
          // debugShowCheckedModeBanner: false,
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
            useMaterial3: true,
            fontFamily: 'HarmonyOS Sans SC', // 应用中文字体
          ),
          builder: (context, child) {
            // 应用全局缩放 - 只使用textScaleFactor，避免Transform.scale造成的放大镜效果
            final scaleFactor = DisplayService.instance.scaleFactor;
            return MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaleFactor: scaleFactor,
              ),
              child: GlobalTapRipple(child: child ?? const SizedBox.shrink()),
            );
          },
          routes: {
            '/settings': (context) => const SettingsPage(),
          },
          home: const ClockScreen(),
        );
      },
    );
  }
}

class ClockScreen extends StatefulWidget {
  const ClockScreen({super.key});

  @override
  State<ClockScreen> createState() => _ClockScreenState();
}

class _ClockScreenState extends State<ClockScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // 使用ValueNotifier替代直接的状态变量，这样可以只在值变化时通知监听者
  final timeNotifier = ValueNotifier<DateTime>(DateTime.now());
  final wifiStatusNotifier = ValueNotifier<bool>(false);
  final mqttStatusNotifier = ValueNotifier<bool>(false);

  late Timer _timeTimer;
  late Timer _statusTimer;
  Timer? _wifiPollTimer;
  StreamSubscription<WiFiStatus>? _wifiStatusSubscription;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);

    // 初始化时间
    timeNotifier.value = DateTime.now();

    // 更新时间的定时器 - 改为每秒更新一次，并且只在秒数变化时才更新UI
    _timeTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      final newTime = DateTime.now();
      // 只有当秒数变化时才更新通知器
      if (timeNotifier.value.second != newTime.second) {
        timeNotifier.value = newTime;
      }
    });

    // 模拟WiFi和MQTT状态检查 - 减少更新频率到每2秒一次
    _statusTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      // 仅保留 MQTT 的示例更新，WiFi 状态由模块流驱动
      const newMqttStatus = true; // TODO: 替换为真实 MQTT 状态
      if (mqttStatusNotifier.value != newMqttStatus) {
        mqttStatusNotifier.value = newMqttStatus;
      }
    });

    // 订阅 WiFi 模块状态流，驱动主界面图标
    final wifiModule = WebSocketServiceManager.instance.wifiModule;
    if (wifiModule != null) {
      _wifiStatusSubscription = wifiModule.statusStream.listen((status) {
        final connected = status.enabled && status.connected;
        if (wifiStatusNotifier.value != connected) {
          wifiStatusNotifier.value = connected;
        }
      });
      // 获取一次初始状态
      wifiModule.getStatus().catchError((_) => null);

      // 在主页周期性轮询 WiFi 状态（每 10 秒）
      _wifiPollTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
        wifiModule.getStatus().catchError((_) => null);
      });
    }
  }

  @override
  void dispose() {
    // 清理资源
    _timeTimer.cancel();
    _statusTimer.cancel();
    // 取消 WiFi 轮询定时器
    _wifiPollTimer?.cancel();
    _wifiStatusSubscription?.cancel();
    timeNotifier.dispose();
    wifiStatusNotifier.dispose();
    mqttStatusNotifier.dispose();
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 获取屏幕尺寸
    final screenSize = MediaQuery.of(context).size;
    final screenWidth = screenSize.width;
    final screenHeight = screenSize.height;

    // 计算侧边栏宽度
    final sidePanelWidth = screenWidth * sidePanelWidthRatio;

    return Scaffold(
      body: Container(
        // 背景图片不需要频繁重建，放在最外层
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage(
                'source/background/1622002094_B8946A9D258FB08AAF74435234C70DF7.jpg'),
            fit: BoxFit.cover,
          ),
        ),
        child: Stack(
          children: [
            // 底部装饰2 - 菱形和状态图标组合组件
            Positioned(
              left: 0,
              right: 0,
              top: screenHeight * 0.6,
              height: screenHeight * (0.1 + 0.15),
              // 使用独立组件，只在连接状态变化时更新
              child: StatusIconsComponent(
                screenWidth: screenWidth,
                screenHeight: screenHeight,
                sidePanelWidth: sidePanelWidth,
                wifiStatusNotifier: wifiStatusNotifier,
                mqttStatusNotifier: mqttStatusNotifier,
              ),
            ),

            // 底部梯形和日期时间组合组件
            Positioned(
              bottom: 0,
              left: 0,
              right: sidePanelWidth,
              height: screenHeight * 0.3,
              // 使用独立组件，只在时间变化时更新
              child: DateTimeComponent(
                screenWidth: screenWidth,
                screenHeight: screenHeight,
                sidePanelWidth: sidePanelWidth,
                timeNotifier: timeNotifier,
              ),
            ),

            // 右侧垂直TabBar - 不需要频繁更新
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              width: sidePanelWidth,
              child: SideTabBar(
                tabController: _tabController,
                screenWidth: screenWidth,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// 状态图标组件 - 只在连接状态变化时更新
class StatusIconsComponent extends StatelessWidget {
  final double screenWidth;
  final double screenHeight;
  final double sidePanelWidth;
  final ValueNotifier<bool> wifiStatusNotifier;
  final ValueNotifier<bool> mqttStatusNotifier;

  const StatusIconsComponent({
    super.key,
    required this.screenWidth,
    required this.screenHeight,
    required this.sidePanelWidth,
    required this.wifiStatusNotifier,
    required this.mqttStatusNotifier,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // 菱形背景 - 不需要频繁重建
        CustomPaint(
          size: Size(screenWidth, screenHeight * (0.1 + 0.15)),
          painter: DiamondPainter(
            color: Colors.black.withOpacity(0.6),
            sidePanelWidth: sidePanelWidth,
          ),
        ),

        // WiFi/蓝牙状态图标 - 使用ValueListenableBuilder只在状态变化时更新
        ValueListenableBuilder<bool>(
          valueListenable: wifiStatusNotifier,
          builder: (context, wifiConnected, child) {
            return Positioned(
              left: (screenWidth - sidePanelWidth) / 3 -
                  (screenHeight > screenWidth
                          ? screenWidth * 0.08
                          : screenHeight * 0.08) /
                      2,
              // y = x*k+b-iconSize/2
              top: ((screenWidth - sidePanelWidth) / 3 -
                          (screenHeight > screenWidth
                                  ? screenWidth * 0.08
                                  : screenHeight * 0.08) /
                              2) *
                      (-0.15 * screenHeight) /
                      (screenWidth - sidePanelWidth) +
                  (0.2 * screenHeight) -
                  (screenHeight > screenWidth
                          ? screenWidth * 0.08
                          : screenHeight * 0.08) /
                      2,
              child: _buildStatusIcon(
                context,
                wifiConnected
                    ? 'source/ico/bluetoothon.svg'
                    : 'source/ico/bluetoothoff.svg',
                Colors.white,
              ),
            );
          },
        ),

        // wifi图标 - 使用ValueListenableBuilder只在状态变化时更新
        ValueListenableBuilder<bool>(
          valueListenable: wifiStatusNotifier,
          builder: (context, wifiConnected, child) {
            return Positioned(
              left: (screenWidth - sidePanelWidth) / 3 * 2 -
                  (screenHeight > screenWidth
                          ? screenWidth * 0.08
                          : screenHeight * 0.08) /
                      2,
              top: ((screenWidth - sidePanelWidth) / 3 * 2 -
                          (screenHeight > screenWidth
                                  ? screenWidth * 0.08
                                  : screenHeight * 0.08) /
                              2) *
                      (-0.15 * screenHeight) /
                      (screenWidth - sidePanelWidth) +
                  (0.2 * screenHeight) -
                  (screenHeight > screenWidth
                          ? screenWidth * 0.08
                          : screenHeight * 0.08) /
                      2,
              child: _buildStatusIcon(
                context,
                wifiConnected
                    ? 'source/ico/wifi_on.svg'
                    : 'source/ico/wifi_off.svg',
                Colors.white,
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildStatusIcon(BuildContext context, String assetPath, Color color) {
    final iconSize =
        screenHeight > screenWidth ? screenWidth * 0.08 : screenHeight * 0.08;
    return SizedBox(
      width: iconSize,
      height: iconSize,
      child: Center(
        child: SvgPicture.asset(
          assetPath,
          width: iconSize,
          height: iconSize,
          colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
        ),
      ),
    );
  }
}

// 日期时间组件 - 使用RepaintBoundary隔离重绘区域
class DateTimeComponent extends StatelessWidget {
  final double screenWidth;
  final double screenHeight;
  final double sidePanelWidth;
  final ValueNotifier<DateTime> timeNotifier;

  const DateTimeComponent({
    super.key,
    required this.screenWidth,
    required this.screenHeight,
    required this.sidePanelWidth,
    required this.timeNotifier,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // 梯形背景 - 使用RepaintBoundary隔离，防止重绘
        RepaintBoundary(
          child: CustomPaint(
            size: Size(screenWidth - sidePanelWidth, screenHeight * 0.3),
            painter: TrapezoidPainter1(
              color: const Color(0xFF567C8C).withOpacity(0.8),
              sidePanelWidth: 0,
            ),
          ),
        ),
        // 日期/星期/时间内容 - 固定在 DateTimeComponent 的底部，使用 Align + Padding
        Positioned(
          left: 0,
          right: 0,
          bottom: screenHeight * 0.01,
          child: RepaintBoundary(
            child: DateDisplayContent(
              screenWidth: screenWidth,
              screenHeight: screenHeight,
              timeNotifier: timeNotifier,
            ),
          ),
        ),
      ],
    );
  }
}

// 日期显示内容组件 - 完全静态，不需要随时间更新
class DateDisplayContent extends StatelessWidget {
  final double screenWidth;
  final double screenHeight;
  final ValueNotifier<DateTime>? timeNotifier;

  const DateDisplayContent({
    super.key,
    required this.screenWidth,
    required this.screenHeight,
    this.timeNotifier,
  });

  @override
  Widget build(BuildContext context) {
    // 获取当前时间，但只用于初始化日期和星期
    final now = DateTime.now();
    final dateFormat = DateFormat('yyyy-MM-dd');
    final dayFormat = DateFormat('EEEE');

    // 格式化日期和星期（这部分不需要每秒更新）
    final date = dateFormat.format(now);
    final day = dayFormat.format(now);

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: screenWidth * 0.1),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Row(
          children: [
            // 星期（左侧）
            Expanded(
              flex: 1,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  day,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: screenHeight > screenWidth
                        ? screenWidth * 0.04
                        : screenHeight * 0.04,
                  ),
                ),
              ),
            ),

            // 日期和时间纵向排列，右对齐
            Expanded(
              flex: 2,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    date,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: screenHeight > screenWidth
                          ? screenWidth * 0.04
                          : screenHeight * 0.04,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),

                  // 如果提供了 timeNotifier，则显示动态时间，否则仅占位
                  if (timeNotifier != null)
                    ValueListenableBuilder<DateTime>(
                      valueListenable: timeNotifier!,
                      builder: (context, currentTime, child) {
                        final timeFormat =
                            DateFormat(showSeconds ? 'HH:mm:ss' : 'HH:mm');
                        final time = timeFormat.format(currentTime);
                        return Text(
                          time,
                          style: TextStyle(
                            color: const Color(0xFFDBA7AF),
                            fontSize: screenHeight > screenWidth
                                ? screenWidth * 0.07
                                : screenHeight * 0.07,
                            fontWeight: FontWeight.bold,
                          ),
                          overflow: TextOverflow.ellipsis,
                        );
                      },
                    )
                  else
                    SizedBox(height: screenHeight * 0.07),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// 只显示时间的组件 - 只有这部分会随秒数变化而更新
class TimeOnlyDisplay extends StatelessWidget {
  final ValueNotifier<DateTime> timeNotifier;
  final double screenWidth;
  final double screenHeight;

  const TimeOnlyDisplay({
    super.key,
    required this.timeNotifier,
    required this.screenWidth,
    required this.screenHeight,
  });

  @override
  Widget build(BuildContext context) {
    // 只有这个组件会随着秒数变化而重建
    return ValueListenableBuilder<DateTime>(
      valueListenable: timeNotifier,
      builder: (context, currentTime, child) {
        // 根据全局变量控制是否显示秒
        final timeFormat = DateFormat(showSeconds ? 'HH:mm:ss' : 'HH:mm');
        final time = timeFormat.format(currentTime);

        return Text(
          time,
          style: TextStyle(
            color: const Color(0xFFDBA7AF),
            fontSize: screenHeight > screenWidth
                ? screenWidth * 0.07
                : screenHeight * 0.07,
            fontWeight: FontWeight.bold,
          ),
          overflow: TextOverflow.ellipsis,
        );
      },
    );
  }
}

// 侧边栏组件 - 不需要频繁更新
class SideTabBar extends StatelessWidget {
  final TabController tabController;
  final double screenWidth;

  const SideTabBar({
    super.key,
    required this.tabController,
    required this.screenWidth,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFB5C9D1).withOpacity(0.9),
      child: RotatedBox(
        quarterTurns: 1, // 旋转TabBar使其垂直
        child: TabBar(
          controller: tabController,
          indicatorColor: Colors.transparent,
          tabs: [
            RotatedBox(
              quarterTurns: 3,
              child: Tab(
                icon: SvgPicture.asset(
                  'source/ico/setting.svg',
                  width: screenWidth * 0.08,
                  height: screenWidth * 0.08,
                  colorFilter:
                      const ColorFilter.mode(Colors.white, BlendMode.srcIn),
                ),
              ),
            ),
            RotatedBox(
              quarterTurns: 3,
              child: Tab(
                icon: SvgPicture.asset(
                  'source/ico/calendar.svg',
                  width: screenWidth * 0.08,
                  height: screenWidth * 0.08,
                  colorFilter:
                      const ColorFilter.mode(Colors.white, BlendMode.srcIn),
                ),
              ),
            ),
            RotatedBox(
              quarterTurns: 3,
              child: Tab(
                icon: SvgPicture.asset(
                  'source/ico/modular.svg',
                  width: screenWidth * 0.08,
                  height: screenWidth * 0.08,
                  colorFilter:
                      const ColorFilter.mode(Colors.white, BlendMode.srcIn),
                ),
              ),
            ),
            RotatedBox(
              quarterTurns: 3,
              child: Tab(
                icon: SvgPicture.asset(
                  'source/ico/a-VoiceAssistants.svg',
                  width: screenWidth * 0.08,
                  height: screenWidth * 0.08,
                  colorFilter:
                      const ColorFilter.mode(Colors.white, BlendMode.srcIn),
                ),
              ),
            ),
          ],
          onTap: (index) {
            switch (index) {
              case 0:
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const SettingsPage()),
                );
                break;
              case 1:
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const CalendarPage()),
                );
                break;
              case 2:
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const CloudPage()),
                );
                break;
              case 3:
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const LoadingPage()),
                );
                break;
            }
          },
        ),
      ),
    );
  }
}

// 梯形绘制器1 - 底部装饰1
class TrapezoidPainter1 extends CustomPainter {
  final Color color;
  final double sidePanelWidth;

  TrapezoidPainter1({required this.color, required this.sidePanelWidth});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    // 根据LVGL代码中的坐标点创建梯形，修正左上与右上高度逻辑
    final path = Path()
      ..moveTo(0, size.height * 0.5) // 左上
      ..lineTo(size.width - sidePanelWidth, 0) // 右上
      ..lineTo(size.width - sidePanelWidth, size.height) // 右下
      ..lineTo(0, size.height)
      ..close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(TrapezoidPainter1 oldDelegate) =>
      color != oldDelegate.color ||
      sidePanelWidth != oldDelegate.sidePanelWidth;
}

// 菱形绘制器 - 底部装饰2
class DiamondPainter extends CustomPainter {
  final Color color;
  final double sidePanelWidth;

  DiamondPainter({required this.color, required this.sidePanelWidth});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final path = Path()
      ..moveTo(0, size.height * 0.6) // 左上
      ..lineTo(size.width - sidePanelWidth, 0) // 右上
      ..lineTo(size.width - sidePanelWidth, size.height * 0.40) // 右下
      ..lineTo(0, size.height) // 左下
      ..close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(DiamondPainter oldDelegate) =>
      color != oldDelegate.color ||
      sidePanelWidth != oldDelegate.sidePanelWidth;
}
