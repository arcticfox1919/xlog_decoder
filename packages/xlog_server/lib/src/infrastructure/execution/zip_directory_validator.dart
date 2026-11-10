import 'dart:io';
import 'dart:typed_data';

import 'zip_limits.dart';

/// Bounds metadata before the ZIP library allocates its directory entries.
class ZipDirectoryValidator {
  const ZipDirectoryValidator({this.limits = const ZipLimits()});

  final ZipLimits limits;

  void validate(File file) {
    final reader = file.openSync();
    try {
      final length = reader.lengthSync();
      final tailSize = length.clamp(0, 65557);
      reader.setPositionSync(length - tailSize);
      final tail = reader.readSync(tailSize);
      final view = ByteData.sublistView(tail);
      for (var offset = tail.length - 22; offset >= 0; offset--) {
        if (view.getUint32(offset, Endian.little) != 0x06054b50) continue;
        final commentLength = view.getUint16(offset + 20, Endian.little);
        if (offset + 22 + commentLength != tail.length) continue;
        final disk = view.getUint16(offset + 4, Endian.little);
        final centralDisk = view.getUint16(offset + 6, Endian.little);
        final diskEntries = view.getUint16(offset + 8, Endian.little);
        final entries = view.getUint16(offset + 10, Endian.little);
        final size = view.getUint32(offset + 12, Endian.little);
        final centralOffset = view.getUint32(offset + 16, Endian.little);
        final zip64 =
            offset >= 20 &&
            view.getUint32(offset - 20, Endian.little) == 0x07064b50;
        if (zip64 ||
            disk != 0 ||
            centralDisk != 0 ||
            diskEntries != entries ||
            entries > limits.maxEntries ||
            size > limits.maxCentralDirectoryBytes ||
            centralOffset + size > length - tailSize + offset) {
          throw const FormatException('ZIP directory limit exceeded');
        }
        return;
      }
      throw const FormatException('Invalid ZIP directory');
    } finally {
      reader.closeSync();
    }
  }
}
