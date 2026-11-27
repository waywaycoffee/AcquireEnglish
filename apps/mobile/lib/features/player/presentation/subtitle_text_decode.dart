import 'dart:convert';
import 'dart:typed_data';

import 'package:gbk_codec/gbk_codec.dart';

/// Decode SRT/VTT bytes: UTF-8 (BOM ok) → UTF-16 LE/BE → GBK → malformed UTF-8.
///
/// Chinese softsubs from netdisk/desktop often arrive as GBK/ANSI; forcing UTF-8
/// yields 乱码 and can break cue parsing enough to destabilize long-film playback.
String decodeSubtitleBytes(List<int> raw) {
  if (raw.isEmpty) return '';
  List<int> bytes = raw;

  // UTF-8 BOM
  if (bytes.length >= 3 &&
      bytes[0] == 0xEF &&
      bytes[1] == 0xBB &&
      bytes[2] == 0xBF) {
    bytes = bytes.sublist(3);
  }

  // UTF-16 LE BOM
  if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
    return _decodeUtf16(bytes.sublist(2), littleEndian: true);
  }
  // UTF-16 BE BOM
  if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
    return _decodeUtf16(bytes.sublist(2), littleEndian: false);
  }

  try {
    return utf8.decode(bytes);
  } on FormatException {
    // fall through
  }

  try {
    return gbk.decode(bytes);
  } catch (_) {
    // fall through
  }

  return utf8.decode(bytes, allowMalformed: true);
}

String _decodeUtf16(List<int> bytes, {required bool littleEndian}) {
  if (bytes.isEmpty) return '';
  final Uint8List data = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
  final ByteData bd = ByteData.sublistView(data);
  final StringBuffer out = StringBuffer();
  final int limit = data.length - (data.length % 2);
  for (int i = 0; i < limit; i += 2) {
    final int unit = littleEndian
        ? bd.getUint16(i, Endian.little)
        : bd.getUint16(i, Endian.big);
    if (unit == 0) continue;
    out.writeCharCode(unit);
  }
  return out.toString();
}
