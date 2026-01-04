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
import 'package:flutter/services.dart' show rootBundle;
import '../../services/display_service.dart';

class SoftwareInfoPage extends StatefulWidget {
  const SoftwareInfoPage({super.key});

  @override
  State<SoftwareInfoPage> createState() => _SoftwareInfoPageState();
}

class _SoftwareInfoPageState extends State<SoftwareInfoPage> {
  String? _content;
  String? _error;
  bool _loading = true;

  Future<void> _loadContent() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final text = await rootBundle.loadString('source/txt/soft_info.txt');
      setState(() {
        _content = text;
      });
    } catch (e) {
      setState(() {
        _error = '无法加载软件信息文档: $e';
      });
    } finally {
      setState(() {
        _loading = false;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    unawaited(_loadContent());
  }

  @override
  Widget build(BuildContext context) {
    final scale = DisplayService.instance.scaleFactor;
    final iconSize = 24.0 * scale;
    final toolbarHeight = 56.0 * scale;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('软件信息'),
        toolbarHeight: toolbarHeight,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          iconSize: iconSize,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Text(
                      _error!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          _content ?? '',
                          style: const TextStyle(
                            fontSize: 14,
                            height: 1.5,
                            color: Colors.black,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }
}