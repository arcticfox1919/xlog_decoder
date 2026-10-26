import 'dart:typed_data';

import 'cipher.dart';
import 'compression.dart';
import 'format.dart';
import 'frame.dart';
import 'models.dart';

/// Applies legacy transforms, decryption, then decompression in wire order.
class XlogPayloadDecoder {
  XlogPayloadDecoder(this.cipher, this.legacyFormat);

  final XlogCipher cipher;
  final XlogLegacyFormat legacyFormat;

  Uint8List decode(XlogFrame header, {required int maxOutputBytes}) {
    var payload = header.payload;
    final magic = header.magic;
    if (magic.chunked) payload = _joinChunks(payload);
    if (magic.isLegacy) {
      if (!magic.hasSequence || legacyFormat == XlogLegacyFormat.c) {
        final key =
            0xcc ^
            ((magic.hasSequence ? header.sequence : payload.length) & 0xff) ^
            magic.byte;
        payload = Uint8List.fromList([for (final byte in payload) byte ^ key]);
      }
    }
    if (magic.encrypted) {
      payload = cipher.decrypt(payload, header.publicKey);
    }
    return switch (magic.compression) {
      XlogCompression.none => payload,
      XlogCompression.deflate => inflateXlog(payload, maxOutputBytes),
      XlogCompression.zstd => inflateXlogZstd(payload, maxOutputBytes),
    };
  }
}

Uint8List _joinChunks(Uint8List payload) {
  final chunks = BytesBuilder(copy: false);
  final view = ByteData.sublistView(payload);
  var offset = 0;
  while (offset < payload.length) {
    if (offset + 2 > payload.length) {
      throw const FormatException('Truncated legacy chunk length');
    }
    final length = view.getUint16(offset, Endian.little);
    offset += 2;
    if (offset + length > payload.length) {
      throw const FormatException('Truncated legacy chunk payload');
    }
    chunks.add(Uint8List.sublistView(payload, offset, offset + length));
    offset += length;
  }
  return chunks.takeBytes();
}
