import 'dart:async';
import 'dart:typed_data';

import 'cipher.dart';
import 'compression.dart';
import 'frame.dart';
import 'models.dart';
import 'key_selection_exception.dart';
import 'payload_decoder.dart';
import 'stream_decoder.dart';
import 'stream_models.dart';

/// Follows decode_mars_crypt_log_file.py and decode_mars_nocrypt_log_file.py,
/// assuming a little-endian producer. C-only legacy formats are opt-in.
///
/// Async encrypted blocks require the server's 32-byte hex private key. The
/// file contains the client's ephemeral public key, not the server private key.
/// Each [decode] call has independent sequence tracking and an ECDH key cache.
class XlogDecoder {
  /// [privateKeyHex] retains the original single-key recovery behavior.
  /// Passing [privateKeysHex], including an empty iterable, enables automatic
  /// per-frame selection and fatal encrypted-frame selection errors. Both
  /// parameters may be combined; validated candidate scalars are deduplicated.
  XlogDecoder({
    String? privateKeyHex,
    Iterable<String>? privateKeysHex,
    this.legacyFormat = XlogLegacyFormat.python,
    this.strict = false,
    this.maxOutputBytes = 128 * 1024 * 1024,
  }) : _cipher = XlogCipher(privateKeyHex, privateKeysHex: privateKeysHex) {
    if (maxOutputBytes < 1) {
      throw ArgumentError.value(
        maxOutputBytes,
        'maxOutputBytes',
        'Must be > 0',
      );
    }
  }

  final XlogCipher _cipher;
  final XlogLegacyFormat legacyFormat;

  /// Throw on the first issue instead of skipping damaged blocks.
  final bool strict;

  /// Maximum combined decoded output for one invocation.
  final int maxOutputBytes;

  /// Decodes a bounded frame at a time, awaiting every output write.
  ///
  /// Does not retain the complete input/output or lists of diagnostics. Each
  /// block is verified before emission; earlier valid blocks can already have
  /// been written when a later error occurs. The caller owns output commit or
  /// rollback (for example, an atomic temporary-file rename).
  ///
  /// Resource violations are fatal even when [strict] is false. Callback and
  /// source failures propagate, and the upstream subscription is cancelled.
  /// Sources must honor pause and keep their own queues bounded. The caller
  /// must also limit concurrent decode operations to meet its memory budget.
  Future<XlogStreamSummary> decodeTo(
    Stream<List<int>> input, {
    required FutureOr<void> Function(Uint8List bytes) onData,
    void Function(XlogIssue issue)? onIssue,
    void Function(XlogBlock block)? onBlock,
    XlogStreamOptions options = const XlogStreamOptions(),
  }) => decodeXlogTo(
    input,
    cipher: _cipher,
    legacyFormat: legacyFormat,
    strict: strict,
    maxOutputBytes: maxOutputBytes,
    onData: onData,
    onIssue: onIssue,
    onBlock: onBlock,
    options: options,
  );

  XlogDecodeResult decode(Uint8List input) {
    final output = BytesBuilder(copy: false);
    final blocks = <XlogBlock>[];
    final issues = <XlogIssue>[];
    final reader = XlogFrameReader(legacyFormat);
    final payloadDecoder = XlogPayloadDecoder(
      _cipher.newSession(),
      legacyFormat,
    );
    final view = ByteData.sublistView(input);
    var lastSequence = 0;

    void report(XlogIssueKind kind, int pos, String message) {
      final issue = XlogIssue(kind, pos, message);
      if (strict) throw XlogDecodeException(issue);
      issues.add(issue);
    }

    final start = reader.findStart(input, view, count: 2);
    if (start == null) {
      if (input.isNotEmpty) {
        report(XlogIssueKind.framing, 0, 'No valid xlog start found');
      }
      return XlogDecodeResult(output.takeBytes(), blocks, issues);
    }
    if (start > 0) {
      report(XlogIssueKind.framing, 0, 'Skipped $start bytes before log start');
    }

    var offset = start;
    while (offset < input.length) {
      var header = reader.tryRead(input, view, offset);
      if (header == null) {
        final badOffset = offset;
        do {
          offset++;
          header = reader.tryRead(input, view, offset);
        } while (header == null && offset < input.length);
        // Preallocated mmap buffers can have zero padding after the last block.
        if (header == null &&
            blocks.isNotEmpty &&
            Uint8List.sublistView(
              input,
              badOffset,
            ).every((byte) => byte == 0)) {
          break;
        }
        report(
          XlogIssueKind.framing,
          badOffset,
          'Skipped ${offset - badOffset} invalid or truncated bytes',
        );
        if (header == null) break;
      }

      final seq = header.sequence;
      // Some producers skip sequence 2 after initialization, including after
      // restarting and appending to the same file. Accept that startup gap.
      final startupGap = lastSequence == 1 && seq == 3;
      if (seq != 0 &&
          seq != 1 &&
          lastSequence != 0 &&
          !startupGap &&
          seq != lastSequence + 1) {
        report(
          XlogIssueKind.sequence,
          offset,
          'Expected sequence ${lastSequence + 1}, found $seq',
        );
      }
      if (seq != 0) lastSequence = seq;

      try {
        final decoded = payloadDecoder.decode(
          header,
          maxOutputBytes: maxOutputBytes - output.length,
        );
        if (decoded.length > maxOutputBytes - output.length) {
          throw const FormatException('Decoded output exceeds maxOutputBytes');
        }
        output.add(decoded);
        blocks.add(
          XlogBlock(
            offset: offset,
            magic: header.magic.byte,
            sequence: seq,
            beginHour: header.beginHour,
            endHour: header.endHour,
            payloadLength: header.payload.length,
            decodedLength: decoded.length,
          ),
        );
      } on XlogKeySelectionException {
        rethrow;
      } on Exception catch (e) {
        if (_cipher.automatic &&
            (e is XlogOutputLimitException ||
                e is XlogCandidateWindowLimitException)) {
          rethrow;
        }
        report(XlogIssueKind.payload, offset, e.toString());
      } on ArgumentError {
        report(XlogIssueKind.payload, offset, 'Invalid secp256k1 public key');
      }
      offset = header.end;
    }
    return XlogDecodeResult(output.takeBytes(), blocks, issues);
  }
}
