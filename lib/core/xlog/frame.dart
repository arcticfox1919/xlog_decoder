import 'dart:typed_data';

import 'format.dart';
import 'models.dart';

/// Validates framing without decrypting or decompressing the payload.
class XlogFrameReader {
  const XlogFrameReader(this.legacyFormat);
  final XlogLegacyFormat legacyFormat;

  XlogFrame? tryRead(Uint8List input, ByteData view, int offset) {
    if (offset >= input.length) return null;
    final magic = XlogMagic.fromByte(input[offset]);
    if (magic == null) return null;
    if (legacyFormat == XlogLegacyFormat.python && !magic.hasSequence) {
      return null;
    }
    final size = magic.headerSize(legacyFormat);
    if (input.length - offset < size + 1) return null;
    final lengthOffset = magic.hasSequence ? 5 : 1;
    final length = view.getUint32(offset + lengthOffset, Endian.little);
    final end = offset + size + length + 1;
    if (end > input.length || input[end - 1] != 0) return null;
    return XlogFrame(
      input: input,
      offset: offset,
      magic: magic,
      size: size,
      end: end,
      sequence: magic.hasSequence
          ? view.getUint16(offset + 1, Endian.little)
          : 0,
      beginHour: magic.hasSequence ? input[offset + 3] : 0,
      endHour: magic.hasSequence ? input[offset + 4] : 0,
    );
  }

  /// Mirrors GetLogStartPos / IsGoodLogBuffer: the initial search checks two
  /// consecutive frames, while recovery within a file only needs one.
  int? findStart(
    Uint8List input,
    ByteData view, {
    int offset = 0,
    int count = 1,
  }) {
    for (var candidate = offset; candidate < input.length; candidate++) {
      var next = candidate;
      var valid = true;
      for (var i = 0; i < count; i++) {
        if (next == input.length) break;
        final frame = tryRead(input, view, next);
        if (frame == null) {
          valid = false;
          break;
        }
        next = frame.end;
      }
      if (valid) return candidate;
    }
    return null;
  }
}

class XlogFrame {
  const XlogFrame({
    required Uint8List input,
    required this.offset,
    required this.magic,
    required this.size,
    required this.end,
    required this.sequence,
    required this.beginHour,
    required this.endHour,
  }) : _input = input;

  final Uint8List _input;
  final int offset;
  final XlogMagic magic;
  final int size;
  final int end;
  final int sequence;
  final int beginHour;
  final int endHour;

  Uint8List get payload =>
      Uint8List.sublistView(_input, offset + size, end - 1);
  Uint8List get publicKey =>
      Uint8List.sublistView(_input, offset + 9, offset + 73);
}
