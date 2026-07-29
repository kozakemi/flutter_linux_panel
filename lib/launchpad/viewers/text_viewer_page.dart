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
import 'dart:io';

import 'package:flutter/material.dart';

import '../../services/display_service.dart';

class TextViewerPage extends StatefulWidget {
  const TextViewerPage({super.key, required this.path});

  final String path;

  @override
  State<TextViewerPage> createState() => _TextViewerPageState();
}

class _TextViewerPageState extends State<TextViewerPage> {
  static const int _maximumBytes = 1024 * 1024;

  String? _content;
  String? _error;
  bool _truncated = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    RandomAccessFile? handle;
    try {
      final file = File(widget.path);
      final size = await file.length();
      handle = await file.open();
      final bytes =
          await handle.read(size > _maximumBytes ? _maximumBytes : size);
      final content = utf8.decode(bytes, allowMalformed: true);
      if (!mounted) return;
      setState(() {
        _content = content;
        _truncated = size > _maximumBytes;
      });
    } on FileSystemException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = '读取文件失败：${error.message}';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = '读取文件失败：$error';
      });
    } finally {
      await handle?.close();
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
        title: Text(_fileName(widget.path)),
        toolbarHeight: toolbarHeight,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          iconSize: iconSize,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_error!, textAlign: TextAlign.center),
        ),
      );
    }
    if (_content == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_truncated)
          const MaterialBanner(
            content: Text('文件超过 1 MB，仅显示前 1 MB 内容'),
            actions: [SizedBox.shrink()],
          ),
        Expanded(
          child: Scrollbar(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SelectableText(
                  _content!,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    height: 1.4,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  String _fileName(String path) {
    return path.split(RegExp(r'[/\\]')).last;
  }
}
