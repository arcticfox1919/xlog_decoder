import 'models.dart';

enum XlogCompression { none, deflate, zstd }

/// Payload branches follow the bundled Python scripts. The two oldest C-only
/// markers are available only when XlogLegacyFormat.c is selected.
enum XlogMagic {
  oldPlain(0x01),
  oldDeflate(0x02, compression: XlogCompression.deflate),
  legacyPlain(0x03),
  legacyDeflate(0x04, compression: XlogCompression.deflate),
  legacyChunks(0x05, compression: XlogCompression.deflate, chunked: true),
  syncZlib(0x06),
  asyncZlib(0x07, compression: XlogCompression.deflate, encrypted: true),
  syncPlainZlib(0x08),
  asyncPlainZlib(0x09, compression: XlogCompression.deflate),
  syncZstd(0x0a),
  syncPlainZstd(0x0b),
  asyncZstd(0x0c, compression: XlogCompression.zstd, encrypted: true),
  asyncPlainZstd(0x0d, compression: XlogCompression.zstd);

  const XlogMagic(
    this.byte, {
    this.compression = XlogCompression.none,
    this.encrypted = false,
    this.chunked = false,
  });

  final int byte;
  final XlogCompression compression;
  final bool encrypted;
  final bool chunked;

  bool get hasSequence => byte >= 3;
  bool get isLegacy => byte <= 5;

  int headerSize(XlogLegacyFormat legacy) {
    if (!hasSequence) return 5;
    if (isLegacy) return legacy == XlogLegacyFormat.python ? 13 : 9;
    return 73;
  }

  static XlogMagic? fromByte(int byte) =>
      byte >= 1 && byte <= values.length ? values[byte - 1] : null;
}
