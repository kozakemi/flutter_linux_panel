import 'dart:typed_data';
import 'dart:io';
import 'dart:convert';

final Map<String, Uint8List?> _coverCache = {};

Future<Uint8List?> readEmbeddedCover(String path) async {
  if (_coverCache.containsKey(path)) return _coverCache[path];
  final lower = path.toLowerCase();
  try {
    final bytes = await File(path).readAsBytes();
    Uint8List? cover;
    if (lower.endsWith('.mp3')) {
      cover = _extractMp3Cover(bytes);
    } else if (lower.endsWith('.flac')) {
      cover = _extractFlacCover(bytes);
    } else if (lower.endsWith('.ogg') || lower.endsWith('.oga') || lower.endsWith('.opus')) {
      cover = _extractOggCover(bytes);
    }
    _coverCache[path] = cover;
    return cover;
  } catch (_) {
    _coverCache[path] = null;
    return null;
  }
}

Uint8List? _extractMp3Cover(Uint8List data) {
  if (data.length < 10) return null;
  if (data[0] != 0x49 || data[1] != 0x44 || data[2] != 0x33) return null;
  final version = data[3];
  final tagSize = _readSynchsafeInt32(data, 6);
  var offset = 10;
  final end = offset + tagSize;
  while (offset + 10 <= end && offset + 10 <= data.length) {
    final id = String.fromCharCodes(data.sublist(offset, offset + 4));
    int size;
    if (version == 4) {
      size = _readSynchsafeInt32(data, offset + 4);
    } else {
      size = _readInt32(data, offset + 4);
    }
    if (size <= 0) break;
    final frameStart = offset + 10;
    final frameEnd = frameStart + size;
    if (frameEnd > data.length) break;
    if (id == 'APIC') {
      int p = frameStart;
      if (p >= frameEnd) return null;
      final encoding = data[p];
      p += 1;
      int mimeEnd = _indexOfNull(data, p, frameEnd);
      if (mimeEnd == -1) return null;
      p = mimeEnd + 1;
      if (p >= frameEnd) return null;
      p += 1;
      int descEnd;
      if (encoding == 0x00 || encoding == 0x03) {
        descEnd = _indexOfNull(data, p, frameEnd);
        if (descEnd == -1) descEnd = p;
        p = descEnd + 1;
      } else {
        descEnd = _indexOfNullUtf16(data, p, frameEnd);
        if (descEnd == -1) descEnd = p;
        p = descEnd + 2;
      }
      if (p >= frameEnd) return null;
      return Uint8List.sublistView(data, p, frameEnd);
    }
    offset = frameEnd;
  }
  return null;
}

Uint8List? _extractFlacCover(Uint8List data) {
  if (data.length < 4) return null;
  if (!(data[0] == 0x66 && data[1] == 0x4C && data[2] == 0x61 && data[3] == 0x43)) return null;
  var offset = 4;
  while (offset + 4 <= data.length) {
    final header0 = data[offset];
    final isLast = (header0 & 0x80) != 0;
    final blockType = header0 & 0x7F;
    final length = (data[offset + 1] << 16) | (data[offset + 2] << 8) | data[offset + 3];
    final start = offset + 4;
    final end = start + length;
    if (end > data.length) break;
    if (blockType == 6) {
      return _parseFlacPictureData(data, start, end);
    }
    offset = end;
    if (isLast) break;
  }
  return null;
}

Uint8List? _extractOggCover(Uint8List data) {
  final keys = [
    'METADATA_BLOCK_PICTURE=',
    'coverart=',
    'COVERART=',
  ];
  for (final key in keys) {
    final idx = _indexOfAscii(data, key);
    if (idx != -1) {
      final start = idx + key.length;
      final b64 = _readBase64(data, start);
      if (b64.isNotEmpty) {
        try {
          final decoded = base64Decode(b64);
          final pic = _parseFlacPictureData(decoded, 0, decoded.length);
          if (pic != null) return pic;
          if (_looksLikeImage(decoded)) return decoded;
        } catch (_) {}
      }
    }
  }
  return null;
}

Uint8List? _parseFlacPictureData(Uint8List d, int start, int end) {
  int p = start;
  if (p + 4 > end) return null;
  final _ = _readUint32BE(d, p);
  p += 4;
  if (p + 4 > end) return null;
  final mimeLen = _readUint32BE(d, p);
  p += 4 + mimeLen;
  if (p + 4 > end) return null;
  final descLen = _readUint32BE(d, p);
  p += 4 + descLen;
  p += 4 * 4;
  if (p + 4 > end) return null;
  final dataLen = _readUint32BE(d, p);
  p += 4;
  if (p + dataLen > end) return null;
  return Uint8List.sublistView(d, p, p + dataLen);
}

int _readUint32BE(Uint8List d, int i) {
  return (d[i] << 24) | (d[i + 1] << 16) | (d[i + 2] << 8) | d[i + 3];
}

int _indexOfAscii(Uint8List d, String ascii) {
  final pat = ascii.codeUnits;
  for (var i = 0; i + pat.length <= d.length; i++) {
    var ok = true;
    for (var j = 0; j < pat.length; j++) {
      if (d[i + j] != pat[j]) {
        ok = false;
        break;
      }
    }
    if (ok) return i;
  }
  return -1;
}

String _readBase64(Uint8List d, int start) {
  final buf = StringBuffer();
  for (var i = start; i < d.length; i++) {
    final c = d[i];
    final ch = c >= 32 && c <= 126 ? String.fromCharCode(c) : '';
    if (ch.isEmpty) break;
    if (!_isBase64Char(ch)) break;
    buf.write(ch);
  }
  return buf.toString();
}

bool _isBase64Char(String ch) {
  const set = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=';
  return set.contains(ch);
}

bool _looksLikeImage(Uint8List data) {
  if (data.length < 12) return false;
  if (data[0] == 0x89 && data[1] == 0x50 && data[2] == 0x4E && data[3] == 0x47) return true;
  if (data[0] == 0xFF && data[1] == 0xD8 && data[2] == 0xFF) return true;
  if (data[0] == 0x52 && data[1] == 0x49 && data[2] == 0x46 && data[3] == 0x46 &&
      data[8] == 0x57 && data[9] == 0x45 && data[10] == 0x42 && data[11] == 0x50) return true;
  return false;
}

int _readSynchsafeInt32(Uint8List d, int i) {
  return (d[i] << 21) | (d[i + 1] << 14) | (d[i + 2] << 7) | d[i + 3];
}

int _readInt32(Uint8List d, int i) {
  return (d[i] << 24) | (d[i + 1] << 16) | (d[i + 2] << 8) | d[i + 3];
}

int _indexOfNull(Uint8List d, int start, int end) {
  for (var i = start; i < end; i++) {
    if (d[i] == 0x00) return i;
  }
  return -1;
}

int _indexOfNullUtf16(Uint8List d, int start, int end) {
  for (var i = start; i + 1 < end; i += 2) {
    if (d[i] == 0x00 && d[i + 1] == 0x00) return i;
  }
  return -1;
}
