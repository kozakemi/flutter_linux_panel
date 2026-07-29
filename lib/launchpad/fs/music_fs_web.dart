Future<List<String>> scanAudioFiles(
  String dirPath,
  bool Function(String) isAudio, {
  bool recursive = true,
  bool includeHidden = true,
}) async {
  // Web 端无法访问本地文件系统；返回空列表，由上层显示提示
  return <String>[];
}
