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

import 'dart:io';

import 'package:flutter/material.dart';

import '../services/display_service.dart';
import 'file_types.dart';
import 'music_app.dart';
import 'viewers/image_viewer_page.dart';
import 'viewers/text_viewer_page.dart';
import 'viewers/video_player_page.dart';

class FileManagerPage extends StatefulWidget {
  const FileManagerPage({
    super.key,
    this.pickImage = false,
  });

  final bool pickImage;

  @override
  State<FileManagerPage> createState() => _FileManagerPageState();
}

class _FileManagerPageState extends State<FileManagerPage> {
  static const String _storageCardPath = '/mnt/tfcard';

  final List<FileSystemEntity> _entries = [];
  late String _currentPath;
  bool _loading = true;
  String? _error;
  int _loadGeneration = 0;

  String get _homePath =>
      Platform.environment['HOME'] ?? Directory.current.absolute.path;

  @override
  void initState() {
    super.initState();
    _currentPath = _homePath;
    _initialize();
  }

  Future<void> _initialize() async {
    final storageCard = Directory(_storageCardPath);
    final initialPath =
        await storageCard.exists() ? _storageCardPath : _homePath;
    await _loadDirectory(initialPath);
  }

  Future<void> _loadDirectory(String path) async {
    final generation = ++_loadGeneration;
    final directory = Directory(path).absolute;
    if (mounted) {
      setState(() {
        _currentPath = directory.path;
        _loading = true;
        _error = null;
      });
    }

    try {
      if (!await directory.exists()) {
        throw FileSystemException('目录不存在', directory.path);
      }
      final entries = await directory.list(followLinks: false).toList();
      entries.sort(_compareEntries);
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _entries
          ..clear()
          ..addAll(entries);
        _loading = false;
      });
    } on FileSystemException catch (error) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _entries.clear();
        _loading = false;
        _error = '无法读取目录：${error.message}';
      });
    } catch (error) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _entries.clear();
        _loading = false;
        _error = '无法读取目录：$error';
      });
    }
  }

  int _compareEntries(FileSystemEntity left, FileSystemEntity right) {
    final leftIsDirectory = left is Directory;
    final rightIsDirectory = right is Directory;
    if (leftIsDirectory != rightIsDirectory) {
      return leftIsDirectory ? -1 : 1;
    }
    return _fileName(left.path)
        .toLowerCase()
        .compareTo(_fileName(right.path).toLowerCase());
  }

  Future<void> _openEntry(FileSystemEntity entry) async {
    if (entry is Directory) {
      await _loadDirectory(entry.path);
      return;
    }

    try {
      if (!await File(entry.path).exists()) {
        throw FileSystemException('文件不存在', entry.path);
      }
      if (!mounted) return;
      final Widget page;
      switch (fileCategoryForPath(entry.path)) {
        case FileCategory.text:
          page = TextViewerPage(path: entry.path);
          break;
        case FileCategory.image:
          if (widget.pickImage) {
            Navigator.of(context).pop(entry.path);
            return;
          }
          page = ImageViewerPage(path: entry.path);
          break;
        case FileCategory.audio:
          page = MusicAppPage(initialTrackPath: entry.path);
          break;
        case FileCategory.video:
          page = VideoPlayerPage(path: entry.path);
          break;
        case FileCategory.unsupported:
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('暂不支持打开“${_fileName(entry.path)}”')),
          );
          return;
      }
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => page),
      );
    } on FileSystemException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('无法打开文件：${error.message}')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('无法打开文件：$error')),
      );
    }
  }

  Future<void> _goToParent() async {
    final parent = Directory(_currentPath).parent.path;
    if (parent != _currentPath) {
      await _loadDirectory(parent);
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
        title: Text(widget.pickImage ? '选择壁纸' : '文件管理器'),
        toolbarHeight: toolbarHeight,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          iconSize: iconSize,
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          PopupMenuButton<String>(
            icon: Icon(Icons.storage_outlined, size: iconSize),
            tooltip: '选择位置',
            onSelected: _loadDirectory,
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: _storageCardPath,
                child: Text('存储卡'),
              ),
              PopupMenuItem(
                value: _homePath,
                child: const Text('用户目录'),
              ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.arrow_upward),
            iconSize: iconSize,
            tooltip: '返回上级',
            onPressed: Directory(_currentPath).parent.path == _currentPath
                ? null
                : _goToParent,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            iconSize: iconSize,
            tooltip: '刷新',
            onPressed: _loading ? null : () => _loadDirectory(_currentPath),
          ),
        ],
      ),
      body: Column(
        children: [
          _buildBreadcrumbs(),
          const Divider(height: 1),
          Expanded(child: _buildDirectoryBody()),
        ],
      ),
    );
  }

  Widget _buildBreadcrumbs() {
    final segments =
        _currentPath.split('/').where((segment) => segment.isNotEmpty).toList();
    final crumbs = <Widget>[
      _breadcrumbButton('/', '/'),
    ];
    var path = '';
    for (final segment in segments) {
      path = '$path/$segment';
      crumbs
        ..add(const Icon(Icons.chevron_right, size: 18))
        ..add(_breadcrumbButton(segment, path));
    }
    return SizedBox(
      height: 48,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(children: crumbs),
      ),
    );
  }

  Widget _breadcrumbButton(String label, String path) {
    return TextButton(
      onPressed: path == _currentPath ? null : () => _loadDirectory(path),
      child: Text(label),
    );
  }

  Widget _buildDirectoryBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.folder_off_outlined, size: 56),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () => _loadDirectory(_currentPath),
                icon: const Icon(Icons.refresh),
                label: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }
    if (_entries.isEmpty) {
      return const Center(child: Text('此目录为空'));
    }
    return ListView.separated(
      itemCount: _entries.length,
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final entry = _entries[index];
        final isDirectory = entry is Directory;
        final isSelectableImage =
            fileCategoryForPath(entry.path) == FileCategory.image;
        return ListTile(
          leading: Icon(
            isDirectory ? Icons.folder_outlined : iconForFilePath(entry.path),
          ),
          title: Text(
            _fileName(entry.path),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: isDirectory ? const Icon(Icons.chevron_right) : null,
          enabled: !widget.pickImage || isDirectory || isSelectableImage,
          onTap: !widget.pickImage || isDirectory || isSelectableImage
              ? () => _openEntry(entry)
              : null,
        );
      },
    );
  }

  String _fileName(String path) {
    return path.split(RegExp(r'[/\\]')).last;
  }
}
