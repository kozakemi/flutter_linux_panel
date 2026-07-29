import 'dart:io';

import 'package:demo1/launchpad/fs/music_fs.dart';
import 'package:flutter_test/flutter_test.dart';

bool _isAudio(String path) => path.toLowerCase().endsWith('.mp3');

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('music_fs_test');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('非递归模式只返回直接子文件', () async {
    final track = File('${tempDir.path}/song.mp3')..writeAsStringSync('');
    final subDir = Directory('${tempDir.path}/sub')..createSync();
    File('${subDir.path}/nested.mp3').writeAsStringSync('');

    final result = await scanAudioFiles(
      tempDir.path,
      _isAudio,
      recursive: false,
      includeHidden: false,
    );

    expect(result, [track.path]);
  });

  test('跳过隐藏文件与隐藏目录', () async {
    final track = File('${tempDir.path}/visible.mp3')..writeAsStringSync('');
    File('${tempDir.path}/.hidden.mp3').writeAsStringSync('');
    final hiddenDir = Directory('${tempDir.path}/.cache')..createSync();
    File('${hiddenDir.path}/cached.mp3').writeAsStringSync('');

    final result = await scanAudioFiles(
      tempDir.path,
      _isAudio,
      includeHidden: false,
    );

    expect(result, [track.path]);
  });

  test('无权限子目录被跳过，扫描不整体失败', () async {
    final track = File('${tempDir.path}/song.mp3')..writeAsStringSync('');
    final lockedDir = Directory('${tempDir.path}/locked')..createSync();
    File('${lockedDir.path}/secret.mp3').writeAsStringSync('');
    // 移除读/执行权限，模拟 Permission denied
    await Process.run('chmod', ['000', lockedDir.path]);
    addTearDown(() => Process.run('chmod', ['755', lockedDir.path]));

    final result = await scanAudioFiles(tempDir.path, _isAudio);

    expect(result, [track.path]);
  });

  test('路径不存在时抛出 FileSystemException', () async {
    expect(
      () => scanAudioFiles('${tempDir.path}/not_exists', _isAudio),
      throwsA(isA<FileSystemException>()),
    );
  });
}
