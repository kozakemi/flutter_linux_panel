import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:demo1/launchpad/file_types.dart';

void main() {
  group('fileExtension', () {
    test('返回小写扩展名', () {
      expect(fileExtension('/tmp/Foo.TXT'), 'txt');
      expect(fileExtension('song.MP3'), 'mp3');
    });

    test('无扩展名返回空字符串', () {
      expect(fileExtension('/tmp/README'), '');
      expect(fileExtension('Makefile'), '');
    });

    test('隐藏文件（以点开头且无其他点）视为无扩展名', () {
      expect(fileExtension('/home/user/.bashrc'), '');
      expect(fileExtension('.gitignore'), '');
    });

    test('以点结尾视为无扩展名', () {
      expect(fileExtension('archive.'), '');
    });

    test('多点文件取最后一段', () {
      expect(fileExtension('archive.tar.gz'), 'gz');
      expect(fileExtension('my.file.name.png'), 'png');
    });

    test('同时支持正反斜杠分隔符', () {
      expect(fileExtension(r'C:\data\image.PNG'), 'png');
      expect(fileExtension('/mnt/tfcard/movie.MKV'), 'mkv');
    });

    test('隐藏文件带真实扩展名时仍能识别', () {
      expect(fileExtension('/home/user/.config.json'), 'json');
    });
  });

  group('fileCategoryForPath - 文本', () {
    for (final ext in textFileExtensions) {
      test('.$ext 归类为 text', () {
        expect(fileCategoryForPath('note.$ext'), FileCategory.text);
      });
    }
  });

  group('fileCategoryForPath - 图片', () {
    for (final ext in imageFileExtensions) {
      test('.$ext 归类为 image', () {
        expect(fileCategoryForPath('pic.$ext'), FileCategory.image);
      });
    }
  });

  group('fileCategoryForPath - 音频', () {
    for (final ext in audioFileExtensions) {
      test('.$ext 归类为 audio', () {
        expect(fileCategoryForPath('sound.$ext'), FileCategory.audio);
      });
    }
  });

  group('fileCategoryForPath - 视频', () {
    for (final ext in videoFileExtensions) {
      test('.$ext 归类为 video', () {
        expect(fileCategoryForPath('clip.$ext'), FileCategory.video);
      });
    }
  });

  group('fileCategoryForPath - 未支持类型', () {
    for (final path in <String>[
      'archive.zip',
      'app.exe',
      'data.bin',
      'document.pdf',
      'noextension',
      '/home/user/.bashrc',
      'trailingdot.',
    ]) {
      test('$path 归类为 unsupported', () {
        expect(fileCategoryForPath(path), FileCategory.unsupported);
      });
    }

    test('大小写混合的未知扩展名仍为 unsupported', () {
      expect(fileCategoryForPath('SETUP.EXE'), FileCategory.unsupported);
    });
  });

  group('分类扩展名集合互不重叠', () {
    test('文本/图片/音频/视频集合两两无交集', () {
      final sets = <String, Set<String>>{
        'text': textFileExtensions,
        'image': imageFileExtensions,
        'audio': audioFileExtensions,
        'video': videoFileExtensions,
      };
      final entries = sets.entries.toList();
      for (var i = 0; i < entries.length; i++) {
        for (var j = i + 1; j < entries.length; j++) {
          final overlap = entries[i].value.intersection(entries[j].value);
          expect(
            overlap,
            isEmpty,
            reason: '${entries[i].key} 与 ${entries[j].key} 存在重叠扩展名: $overlap',
          );
        }
      }
    });
  });

  group('图标映射', () {
    test('每个分类都有对应图标', () {
      expect(
          iconForFileCategory(FileCategory.text), Icons.description_outlined);
      expect(iconForFileCategory(FileCategory.image), Icons.image_outlined);
      expect(
          iconForFileCategory(FileCategory.audio), Icons.audio_file_outlined);
      expect(
          iconForFileCategory(FileCategory.video), Icons.video_file_outlined);
      expect(iconForFileCategory(FileCategory.unsupported),
          Icons.insert_drive_file_outlined);
    });

    test('iconForFilePath 与路径分类一致', () {
      expect(iconForFilePath('a.txt'), Icons.description_outlined);
      expect(iconForFilePath('a.png'), Icons.image_outlined);
      expect(iconForFilePath('a.mp3'), Icons.audio_file_outlined);
      expect(iconForFilePath('a.mp4'), Icons.video_file_outlined);
      expect(iconForFilePath('a.zip'), Icons.insert_drive_file_outlined);
    });
  });

  // 目录浏览的排序/回退逻辑目前封装在 FileManagerPage 的私有 State 中，
  // 无法直接单测。此处用临时目录验证与页面等价的“目录优先 + 名称忽略大小写排序”
  // 约定，以及入口回退所依赖的目录存在性判断，锁定行为契约。
  group('目录浏览行为契约（临时目录）', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('file_manager_test_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    int compareEntries(FileSystemEntity left, FileSystemEntity right) {
      final leftIsDir = left is Directory;
      final rightIsDir = right is Directory;
      if (leftIsDir != rightIsDir) {
        return leftIsDir ? -1 : 1;
      }
      String name(String path) => path.split(RegExp(r'[/\\]')).last;
      return name(left.path)
          .toLowerCase()
          .compareTo(name(right.path).toLowerCase());
    }

    test('目录优先且按名称忽略大小写排序', () async {
      await Directory('${tempDir.path}/Beta').create();
      await Directory('${tempDir.path}/alpha').create();
      await File('${tempDir.path}/Zeta.txt').create();
      await File('${tempDir.path}/apple.png').create();

      final entries = await tempDir.list(followLinks: false).toList()
        ..sort(compareEntries);

      final names = entries.map((e) => e.path.split('/').last).toList();
      expect(names, ['alpha', 'Beta', 'apple.png', 'Zeta.txt']);
    });

    test('空目录列举结果为空', () async {
      final entries = await tempDir.list(followLinks: false).toList();
      expect(entries, isEmpty);
    });

    test('入口回退依赖的目录存在性判断', () async {
      expect(await tempDir.exists(), isTrue);
      final missing = Directory('${tempDir.path}/does_not_exist');
      expect(await missing.exists(), isFalse);
    });
  });
}
