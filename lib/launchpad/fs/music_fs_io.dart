import 'dart:io';

Future<List<String>> scanAudioFiles(
  String dirPath,
  bool Function(String) isAudio,
) async {
  final dir = Directory(dirPath);
  final exists = await dir.exists();
  if (!exists) {
    throw FileSystemException('路径不存在', dirPath);
  }

  final entries = dir
      .listSync(recursive: true, followLinks: false)
      .whereType<File>()
      .map((f) => f.path)
      .where((p) => isAudio(p))
      .toList()
    ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

  return entries;
}