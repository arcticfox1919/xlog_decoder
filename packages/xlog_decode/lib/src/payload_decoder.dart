import 'dart:typed_data';

import 'cipher.dart';
import 'candidate_decompression.dart';
import 'key_selection_exception.dart';
import 'compression.dart';
import 'format.dart';
import 'frame.dart';
import 'models.dart';

/// Applies legacy transforms, decryption, then decompression in wire order.
class XlogPayloadDecoder {
  XlogPayloadDecoder(this.cipher, this.legacyFormat);

  final XlogCipher cipher;
  final XlogLegacyFormat legacyFormat;

  Uint8List decode(
    XlogFrame header, {
    required int maxOutputBytes,
    int? maxZstdWindowBytes,
  }) {
    var payload = header.payload;
    final magic = header.magic;
    if (magic.chunked) payload = _joinChunks(payload);
    if (magic.isLegacy) {
      if (!magic.hasSequence || legacyFormat == XlogLegacyFormat.c) {
        final key =
            0xcc ^
            ((magic.hasSequence ? header.sequence : payload.length) & 0xff) ^
            magic.byte;
        final transformed = Uint8List(payload.length);
        for (var i = 0; i < payload.length; i++) {
          transformed[i] = payload[i] ^ key;
        }
        payload = transformed;
      }
    }
    if (magic.encrypted && cipher.automatic) {
      if (cipher.candidateCount == 0) {
        throw const XlogKeySelectionException(
          XlogKeySelectionFailure.missingKeys,
        );
      }
      Uint8List? accepted;
      for (var candidate = 0; candidate < cipher.candidateCount; candidate++) {
        Uint8List decoded;
        try {
          final decrypted = cipher.decrypt(
            payload,
            header.publicKey,
            candidate: candidate,
          );
          decoded = _decompress(
            decrypted,
            magic.compression,
            maxOutputBytes,
            maxZstdWindowBytes,
            candidate: true,
          );
        } on XlogOutputLimitException {
          rethrow;
        } on XlogCandidateWindowLimitException {
          rethrow;
        } on Exception {
          continue;
        } on ArgumentError {
          continue;
        }
        if (accepted == null) {
          accepted = decoded;
        } else if (!_sameBytes(accepted, decoded)) {
          throw const XlogKeySelectionException(
            XlogKeySelectionFailure.ambiguousKeys,
          );
        }
      }
      if (accepted == null) {
        throw const XlogKeySelectionException(
          XlogKeySelectionFailure.noMatchingKey,
        );
      }
      return accepted;
    }
    if (magic.encrypted) payload = cipher.decrypt(payload, header.publicKey);
    return _decompress(
      payload,
      magic.compression,
      maxOutputBytes,
      maxZstdWindowBytes,
    );
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

Uint8List _decompress(
  Uint8List payload,
  XlogCompression compression,
  int limit,
  int? window, {
  bool candidate = false,
}) => switch (compression) {
  XlogCompression.none => payload,
  XlogCompression.deflate =>
    candidate ? inflateCandidate(payload, limit) : inflateXlog(payload, limit),
  XlogCompression.zstd => inflateXlogZstd(
    payload,
    limit,
    maxWindowBytes: window,
    candidate: candidate,
  ),
};

bool _sameBytes(Uint8List first, Uint8List second) {
  if (first.length != second.length) return false;
  for (var i = 0; i < first.length; i++) {
    if (first[i] != second[i]) return false;
  }
  return true;
}
