import 'dart:typed_data';

import 'package:archive/archive.dart';

/// Internal typed marker, translated to an operation limit by decodeTo.
class XlogOutputLimitException extends FormatException {
  const XlogOutputLimitException()
    : super('Decoded output exceeds maxOutputBytes');
}

Uint8List _append(Uint8List bytes, List<int> suffix) =>
    Uint8List(bytes.length + suffix.length)
      ..setRange(0, bytes.length, bytes)
      ..setRange(bytes.length, bytes.length + suffix.length, suffix);

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
  final bytes = flushed ? _append(payload, [1, 0, 0, 255, 255]) : payload;
  final stream = const ZLibDecoderWeb().decodeLazy(
    InputMemoryStream(bytes),
    raw: true,
  );
  final decoded = stream.readBytes(remaining + 1).toUint8List();
  if (decoded.length > remaining) {
    throw const XlogOutputLimitException();
  }
  return decoded;
}

/// Mars stores ZSTD_e_flush output and discards the frame terminator. Accept
/// that precise case only: a frame ending at a complete block boundary, with
/// no checksum or declared content size. Other truncation remains an error.
Uint8List _finishZstdFrame(Uint8List bytes, {int? candidateWindowLimit}) {
  var offset = 0;
  while (offset < bytes.length) {
    if (offset + 6 > bytes.length ||
        bytes[offset] != 0x28 ||
        bytes[offset + 1] != 0xb5 ||
        bytes[offset + 2] != 0x2f ||
        bytes[offset + 3] != 0xfd) {
      throw const FormatException('Invalid or truncated Zstandard frame');
    }
    final frameStart = offset;
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
    if (candidateWindowLimit != null) {
      var window = 0;
      if (singleSegment) {
        final sizeStart = offset - sizeLength;
        for (var i = sizeLength - 1; i >= 0; i--) {
          window = window * 256 + bytes[sizeStart + i];
          if (window > candidateWindowLimit) break;
        }
        if (sizeFlag == 1) window += 256;
      } else {
        final descriptor = bytes[frameStart + 5];
        final log = 10 + (descriptor >> 3);
        final base = log == 31 ? 0x80000000 : (log < 31 ? 1 << log : 0);
        window = log > 31
            ? candidateWindowLimit + 1
            : base + (base ~/ 8) * (descriptor & 7);
      }
      if (window > candidateWindowLimit) {
        throw XlogCandidateWindowLimitException(candidateWindowLimit, window);
      }
    }
    var blockCount = 0;
    while (true) {
      if (offset == bytes.length &&
          blockCount > 0 &&
          sizeLength == 0 &&
          descriptor & 4 == 0) {
        return _append(bytes, [1, 0, 0]);
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

Uint8List inflateXlogZstd(
  Uint8List payload,
  int maxOutputBytes, {
  int? maxWindowBytes,
  bool candidate = false,
}) {
  final stream =
      ZstdDecoder(
        maxWindowSize: maxWindowBytes ?? zstdDefaultMaxWindowSize,
      ).decodeLazy(
        InputMemoryStream(
          _finishZstdFrame(
            payload,
            candidateWindowLimit: candidate
                ? (maxWindowBytes ?? zstdDefaultMaxWindowSize)
                : null,
          ),
        ),
        verify: true,
      );
  final decoded = stream.readBytes(maxOutputBytes + 1).toUint8List();
  if (decoded.length > maxOutputBytes) {
    throw const XlogOutputLimitException();
  }
  return decoded;
}

/// Internal automatic-candidate marker. This is never retried as a wrong key.
class XlogCandidateWindowLimitException extends FormatException {
  XlogCandidateWindowLimitException(this.limit, this.actual)
    : super('Zstandard window exceeds configured limit');
  final int limit;
  final int actual;
}
