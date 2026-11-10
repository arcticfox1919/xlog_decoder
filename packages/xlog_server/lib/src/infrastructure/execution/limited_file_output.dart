import 'dart:typed_data';

import 'package:archive/archive_io.dart';

/// Measures actual decompressed bytes and CRC while extracting onto disk.
class LimitedFileOutput extends OutputStream {
  LimitedFileOutput(String path, this.limit)
    : _output = OutputFileStream(path, bufferSize: 64 * 1024),
      super(byteOrder: ByteOrder.littleEndian);

  final OutputFileStream _output;
  final int limit;
  int crc = 0;

  @override
  int get length => _output.length;

  void _check(int count) {
    if (count < 0 || length + count > limit) {
      throw const FormatException('ZIP entry limit exceeded');
    }
  }

  @override
  void writeByte(int value) {
    _check(1);
    _output.writeByte(value);
    crc = getCrc32([value], crc);
  }

  @override
  void writeBytes(List<int> bytes, {int? length}) {
    final count = length ?? bytes.length;
    _check(count);
    final content = count == bytes.length ? bytes : bytes.sublist(0, count);
    crc = getCrc32(content, crc);
    _output.writeBytes(content);
  }

  @override
  void writeStream(InputStream stream) {
    while (!stream.isEOS) {
      writeBytes(stream.readBytes(64 * 1024).toUint8List());
    }
  }

  @override
  Uint8List subset(int start, [int? end]) => _output.subset(start, end);

  @override
  void clear() => throw UnsupportedError('Cannot clear extraction');

  @override
  void flush() => _output.flush();

  @override
  void closeSync() => _output.closeSync();
}
