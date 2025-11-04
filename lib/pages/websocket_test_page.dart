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

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../services/websocket_service_manager.dart';
//import '../services/wifi_module.dart';
//import '../models/wifi_models.dart';

class WebSocketTestPage extends StatefulWidget {
  const WebSocketTestPage({super.key});

  @override
  State<WebSocketTestPage> createState() => _WebSocketTestPageState();
}

class _WebSocketTestPageState extends State<WebSocketTestPage> {
  String _serviceStatus = '检查中...';
  String _wifiModuleStatus = '检查中...';
  String _connectionDetails = '';
  String _directConnectionStatus = '未连接';
  WebSocketChannel? _directChannel;

  @override
  void initState() {
    super.initState();
    _checkWebSocketStatus();
  }

  Future<void> _checkWebSocketStatus() async {
    try {
      // 检查WebSocket服务管理器状态
      final serviceManager = WebSocketServiceManager.instance;

      setState(() {
        _serviceStatus = serviceManager.isInitialized ? '已初始化' : '未初始化';
      });

      // 检查WiFi模块状态
      final wifiModule = serviceManager.wifiModule;
      if (wifiModule != null) {
        setState(() {
          _wifiModuleStatus = '模块已获取';
          _connectionDetails = '模块ID: ${wifiModule.moduleId}\n'
              'WebSocket路径: ${wifiModule.websocketPath}';
        });

        // 尝试获取WiFi状态来测试连接
        try {
          await wifiModule.getStatus();
          setState(() {
            _wifiModuleStatus = 'WiFi模块连接正常';
          });
        } catch (e) {
          setState(() {
            _wifiModuleStatus = 'WiFi模块连接失败: $e';
          });
        }
      } else {
        setState(() {
          _wifiModuleStatus = 'WiFi模块未找到';
        });
      }
    } catch (e) {
      setState(() {
        _serviceStatus = '检查失败: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('WebSocket状态测试'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'WebSocket服务管理器',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text('状态: $_serviceStatus'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'WiFi模块',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text('状态: $_wifiModuleStatus'),
                    if (_connectionDetails.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(_connectionDetails),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Center(
              child: ElevatedButton(
                onPressed: _checkWebSocketStatus,
                child: const Text('重新检查'),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '直接连接测试 (172.20.10.2:8080)',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text('状态: $_directConnectionStatus'),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        ElevatedButton(
                          onPressed: _connectDirectly,
                          child: const Text('直接连接'),
                        ),
                        ElevatedButton(
                          onPressed: _disconnectDirectly,
                          child: const Text('断开连接'),
                        ),
                        ElevatedButton(
                          onPressed: _sendTestMessage,
                          child: const Text('发送测试消息'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  // 直接连接到WebSocket服务器
  void _connectDirectly() {
    try {
      _directChannel = WebSocketChannel.connect(
        Uri.parse('ws://172.20.10.2:8080/wifi'),
      );
      
      _directChannel!.stream.listen(
        (message) {
          setState(() {
            _directConnectionStatus = '已连接，收到消息: $message';
          });
        },
        onError: (error) {
          setState(() {
            _directConnectionStatus = '连接错误: $error';
          });
        },
        onDone: () {
          setState(() {
            _directConnectionStatus = '连接已关闭';
          });
        },
      );
      
      setState(() {
        _directConnectionStatus = '连接中...';
      });
    } catch (e) {
      setState(() {
        _directConnectionStatus = '连接失败: $e';
      });
    }
  }
  
  // 断开直接连接
  void _disconnectDirectly() {
    if (_directChannel != null) {
      _directChannel!.sink.close();
      _directChannel = null;
      setState(() {
        _directConnectionStatus = '已断开连接';
      });
    }
  }
  
  // 发送测试消息
  void _sendTestMessage() {
    if (_directChannel != null) {
      try {
        final message = {
          'type': 'wifi_status_request',
          'request_id': DateTime.now().millisecondsSinceEpoch.toString(),
        };
        
        _directChannel!.sink.add(jsonEncode(message));
        setState(() {
          _directConnectionStatus = '已发送测试消息';
        });
      } catch (e) {
        setState(() {
          _directConnectionStatus = '发送消息失败: $e';
        });
      }
    } else {
      setState(() {
        _directConnectionStatus = '未连接，无法发送消息';
      });
    }
  }

  @override
  void dispose() {
    _disconnectDirectly();
    super.dispose();
  }
}
