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

enum FileCategory {
  text,
  image,
  audio,
  video,
  unsupported,
}

const Set<String> textFileExtensions = {
  'txt',
  'md',
  'log',
  'json',
  'yaml',
  'yml',
  'xml',
  'csv',
  'ini',
  'conf',
  'dart',
  'c',
  'cc',
  'cpp',
  'h',
  'hpp',
  'sh',
  'py',
};

const Set<String> imageFileExtensions = {
  'jpg',
  'jpeg',
  'png',
  'gif',
  'webp',
  'bmp',
};

const Set<String> audioFileExtensions = {
  'mp3',
  'flac',
  'wav',
  'm4a',
  'aac',
  'ogg',
};

const Set<String> videoFileExtensions = {
  'mp4',
  'mkv',
  'webm',
  'mov',
  'avi',
  'm4v',
  'ts',
};

String fileExtension(String path) {
  final name = path.split(RegExp(r'[/\\]')).last;
  final dotIndex = name.lastIndexOf('.');
  if (dotIndex <= 0 || dotIndex == name.length - 1) {
    return '';
  }
  return name.substring(dotIndex + 1).toLowerCase();
}

FileCategory fileCategoryForPath(String path) {
  final extension = fileExtension(path);
  if (textFileExtensions.contains(extension)) {
    return FileCategory.text;
  }
  if (imageFileExtensions.contains(extension)) {
    return FileCategory.image;
  }
  if (audioFileExtensions.contains(extension)) {
    return FileCategory.audio;
  }
  if (videoFileExtensions.contains(extension)) {
    return FileCategory.video;
  }
  return FileCategory.unsupported;
}

IconData iconForFileCategory(FileCategory category) {
  switch (category) {
    case FileCategory.text:
      return Icons.description_outlined;
    case FileCategory.image:
      return Icons.image_outlined;
    case FileCategory.audio:
      return Icons.audio_file_outlined;
    case FileCategory.video:
      return Icons.video_file_outlined;
    case FileCategory.unsupported:
      return Icons.insert_drive_file_outlined;
  }
}

IconData iconForFilePath(String path) {
  return iconForFileCategory(fileCategoryForPath(path));
}
