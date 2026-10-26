import 'dart:typed_data';

import 'package:archive/archive.dart';

Uint8List inflateXlog(Uint8List payload, int remaining) {
  // Python's decompressobj(-MAX_WBITS).decompress(b'') returns empty bytes.
  if (payload.isEmpty) return Uint8List(0);
  // Z_SYNC_FLUSH produces byte-aligned non-final streams. An empty final
  // stored block makes those streams consumable by a strict DEFLATE decoder.
  final flushed =
      payload.length >= 4 &&
      payload[payload.length - 4] == 0 &&
      payload[payload.length - 3] == 0 &&
      payload[payload.length - 2] == 255 &&
      payload[payload.length - 1] == 255;
  final bytes = flushed ? <int>[...payload, 1, 0, 0, 255, 255] : payload;
  final stream = const ZLibDecoderWeb().decodeLazy(
    InputMemoryStream(bytes),
    raw: true,
  );
  final decoded = stream.readBytes(remaining + 1).toUint8List();
  if (decoded.length > remaining) {
    throw const FormatException('Decoded output exceeds maxOutputBytes');
  }
  return decoded;
}

/// Mars stores ZSTD_e_flush output and discards the frame terminator. Accept
/// that precise case only: a frame ending at a complete block boundary, with
/// no checksum or declared content size. Other truncation remains an error.
Uint8List _finishZstdFrame(Uint8List bytes) {
  var offset = 0;
  while (offset < bytes.length) {
    if (offset + 6 > bytes.length ||
        bytes[offset] != 0x28 ||
        bytes[offset + 1] != 0xb5 ||
        bytes[offset + 2] != 0x2f ||
        bytes[offset + 3] != 0xfd) {
      throw const FormatException('Invalid or truncated Zstandard frame');
    }
    final descriptor = bytes[offset + 4];
    final singleSegment = (descriptor & 0x20) != 0;
    final sizeFlag = descriptor >> 6;
    final sizeLength = sizeFlag == 0
        ? (singleSegment ? 1 : 0)
        : const [0, 2, 4, 8][sizeFlag];
    offset +=
        5 +
        (singleSegment ? 0 : 1) +
        const [0, 1, 2, 4][descriptor & 3] +
        sizeLength;
    if (offset > bytes.length) {
      throw const FormatException('Truncated Zstandard header');
    }
    var blockCount = 0;
    while (true) {
      if (offset == bytes.length &&
          blockCount > 0 &&
          sizeLength == 0 &&
          descriptor & 4 == 0) {
        return Uint8List.fromList([...bytes, 1, 0, 0]);
      }
      if (offset + 3 > bytes.length) {
        throw const FormatException('Truncated Zstandard block header');
      }
      final block =
          bytes[offset] | bytes[offset + 1] << 8 | bytes[offset + 2] << 16;
      final type = (block >> 1) & 3;
      if (type == 3) {
        throw const FormatException('Reserved Zstandard block type');
      }
      offset += 3 + (type == 1 ? 1 : block >> 3);
      if (offset > bytes.length) {
        throw const FormatException('Truncated Zstandard block');
      }
      blockCount++;
      if (block & 1 != 0) break;
    }
    if (descriptor & 4 != 0) offset += 4;
    if (offset > bytes.length) {
      throw const FormatException('Truncated Zstandard checksum');
    }
  }
  if (bytes.isEmpty) throw const FormatException('Empty Zstandard payload');
  return bytes;
}

Uint8List inflateXlogZstd(Uint8List payload, int maxOutputBytes) =>
    ZstdDecoder().decodeBytes(
      _finishZstdFrame(payload),
      verify: true,
      throwOnError: true,
      maxOutputSize: maxOutputBytes,
    );
