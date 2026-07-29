import 'dart:io';

String _baseName(String path) {
  final normalized = path.replaceAll('\\', '/');
  final separator = normalized.lastIndexOf('/');
  return separator < 0 ? normalized : normalized.substring(separator + 1);
}

/// 扫描 [dirPath] 下的音频文件。
///
/// - [recursive] 为 true 时递归子目录，否则只扫描直接子文件。
/// - [includeHidden] 为 false 时跳过以 `.` 开头的隐藏文件/目录。
/// - 无权限或不可读的目录项会被跳过，不会导致整个扫描失败。
Future<List<String>> scanAudioFiles(
  String dirPath,
  bool Function(String) isAudio, {
  bool recursive = true,
  bool includeHidden = true,
}) async {
  final dir = Directory(dirPath);
  final exists = await dir.exists();
  if (!exists) {
    throw FileSystemException('路径不存在', dirPath);
  }

  final results = <String>[];
  final pending = <Directory>[dir];
  while (pending.isNotEmpty) {
    final current = pending.removeLast();
    final List<FileSystemEntity> children;
    try {
      children = current.listSync(followLinks: false);
    } on FileSystemException {
      // 无权限或不可读的目录直接跳过
      continue;
    }
    for (final entity in children) {
      if (!includeHidden && _baseName(entity.path).startsWith('.')) {
        continue;
      }
      if (entity is File) {
        if (isAudio(entity.path)) {
          results.add(entity.path);
        }
      } else if (entity is Directory && recursive) {
        pending.add(entity);
      }
    }
  }

  results.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  return results;
}
