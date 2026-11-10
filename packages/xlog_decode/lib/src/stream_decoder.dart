import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'cipher.dart';
import 'compression.dart';
import 'format.dart';
import 'frame.dart';
import 'models.dart';
import 'key_selection_exception.dart';
import 'payload_decoder.dart';
import 'stream_models.dart';

Future<XlogStreamSummary> decodeXlogTo(
  Stream<List<int>> source, {
  required XlogCipher cipher,
  required XlogLegacyFormat legacyFormat,
  required bool strict,
  required int maxOutputBytes,
  required FutureOr<void> Function(Uint8List) onData,
  required XlogStreamOptions options,
  void Function(XlogIssue)? onIssue,
  void Function(XlogBlock)? onBlock,
}) async {
  options.validate();
  final input = _BufferedInput(source, options);
  final reader = XlogFrameReader(legacyFormat);
  final payloadDecoder = XlogPayloadDecoder(
    cipher.newSession(maxCachedKeys: options.maxCachedKeys),
    legacyFormat,
  );
  var outputBytes = 0;
  var blockCount = 0;
  var issueCount = 0;
  var lastSequence = 0;

  void report(XlogIssueKind kind, int offset, String message) {
    final issue = XlogIssue(kind, offset, message);
    if (strict) throw XlogDecodeException(issue);
    issueCount++;
    onIssue?.call(issue);
  }

  XlogResourceLimitException limit(String resource, int cap, int actual) =>
      XlogResourceLimitException(
        resource: resource,
        limit: cap,
        actual: actual,
        offset: input.offset,
      );

  Future<int?> frameLengthAt(int offset) async {
    if (!await input.ensure(offset + 1)) return null;
    final magic = XlogMagic.fromByte(input.byteAt(offset));
    if (magic == null ||
        (legacyFormat == XlogLegacyFormat.python && !magic.hasSequence)) {
      return null;
    }
    final headerSize = magic.headerSize(legacyFormat);
    if (!await input.ensure(offset + headerSize + 1)) return null;
    final lengthOffset = offset + (magic.hasSequence ? 5 : 1);
    final length = input.uint32At(lengthOffset) + headerSize + 1;
    if (length > options.maxFrameBytes) {
      throw limit('maxFrameBytes', options.maxFrameBytes, length);
    }
    if (!await input.ensure(offset + length)) return null;
    return input.byteAt(offset + length - 1) == 0 ? length : null;
  }

  // Initial acceptance requires two consecutive frames, or one complete frame
  // at actual EOF. Keep the first candidate while looking ahead: if the second
  // is invalid, recovery must still inspect bytes within that first candidate.
  Future<int?> findFrame({required bool initial}) async {
    while (await input.ensure(1)) {
      final length = await frameLengthAt(0);
      if (length != null) {
        if (!initial || !await input.ensure(length + 1)) return length;
        if (await frameLengthAt(length) != null) return length;
      }
      input.discardInvalid();
    }
    return null;
  }

  var failed = false;
  try {
    var length = await findFrame(initial: true);
    if (length == null) {
      if (input.inputBytes > 0) {
        report(XlogIssueKind.framing, 0, 'No valid xlog start found');
      }
    } else {
      if (input.offset > 0) {
        report(
          XlogIssueKind.framing,
          0,
          'Skipped ${input.offset} bytes before log start',
        );
      }
      while (length != null) {
        final offset = input.offset;
        final bytes = input.view;
        final header = reader.tryRead(bytes, ByteData.sublistView(bytes), 0)!;
        final sequence = header.sequence;
        final startupGap = lastSequence == 1 && sequence == 3;
        if (sequence != 0 &&
            sequence != 1 &&
            lastSequence != 0 &&
            !startupGap &&
            sequence != lastSequence + 1) {
          report(
            XlogIssueKind.sequence,
            offset,
            'Expected sequence ${lastSequence + 1}, found $sequence',
          );
        }
        if (sequence != 0) lastSequence = sequence;

        Uint8List? decoded;
        final remaining = maxOutputBytes - outputBytes;
        final budget = math.min(remaining, options.maxDecodedBlockBytes);
        try {
          decoded = payloadDecoder.decode(
            header,
            maxOutputBytes: budget,
            maxZstdWindowBytes: options.maxZstdWindowBytes,
          );
          if (decoded.length > budget) throw const XlogOutputLimitException();
        } on XlogKeySelectionException {
          rethrow;
        } on XlogCandidateWindowLimitException catch (error) {
          throw limit('maxZstdWindowBytes', error.limit, error.actual);
        } on XlogOutputLimitException {
          final totalLimit = remaining <= options.maxDecodedBlockBytes;
          throw limit(
            totalLimit ? 'maxOutputBytes' : 'maxDecodedBlockBytes',
            totalLimit ? maxOutputBytes : options.maxDecodedBlockBytes,
            totalLimit ? outputBytes + budget + 1 : budget + 1,
          );
        } on Exception catch (error) {
          report(XlogIssueKind.payload, offset, error.toString());
        } on ArgumentError {
          report(XlogIssueKind.payload, offset, 'Invalid secp256k1 public key');
        }

        if (decoded != null) {
          // Validate the whole bounded block before emitting anything. A bad
          // checksum must not leak partially recovered bytes into the output.
          for (
            var pos = 0;
            pos < decoded.length;
            pos += options.outputChunkBytes
          ) {
            final end = math.min(
              pos + options.outputChunkBytes,
              decoded.length,
            );
            // Give consumers owned chunks, independent of the reusable parser.
            await onData(
              Uint8List.fromList(Uint8List.sublistView(decoded, pos, end)),
            );
          }
          outputBytes += decoded.length;
          blockCount++;
          onBlock?.call(
            XlogBlock(
              offset: offset,
              magic: header.magic.byte,
              sequence: sequence,
              beginHour: header.beginHour,
              endHour: header.endHour,
              payloadLength: header.payload.length,
              decodedLength: decoded.length,
            ),
          );
        }
        input.discard(length);
        final recoveryOffset = input.offset;
        input.resetInvalid();
        length = await findFrame(initial: false);
        if (input.offset > recoveryOffset &&
            !(length == null && blockCount > 0 && input.invalidWasAllZero)) {
          report(
            XlogIssueKind.framing,
            recoveryOffset,
            'Skipped ${input.offset - recoveryOffset} invalid or truncated bytes',
          );
        }
      }
    }
    return XlogStreamSummary(
      inputBytes: input.inputBytes,
      outputBytes: outputBytes,
      blockCount: blockCount,
      issueCount: issueCount,
      peakBufferedBytes: input.peakBufferedBytes,
    );
  } catch (_) {
    failed = true;
    rethrow;
  } finally {
    try {
      await input.cancel();
    } catch (_) {
      // A failed cleanup must not replace the source/sink/decoder failure.
      if (!failed) rethrow;
    }
  }
}

/// A compacting buffer with at most two encoded frames of lookahead and one
/// bounded upstream event. It never collects the complete file or metadata.
class _BufferedInput {
  _BufferedInput(Stream<List<int>> source, this.options)
    : _source = StreamIterator(source),
      _buffer = Uint8List(math.min(8192, options.maxFrameBytes * 2));

  final StreamIterator<List<int>> _source;
  final XlogStreamOptions options;
  Uint8List _buffer;
  int _start = 0;
  int _end = 0;
  List<int>? _pending;
  int _pendingOffset = 0;
  bool _done = false;
  int offset = 0;
  int inputBytes = 0;
  int peakBufferedBytes = 0;
  bool invalidWasAllZero = true;

  int get length => _end - _start;
  Uint8List get view => Uint8List.sublistView(_buffer, _start, _end);
  int byteAt(int relative) => _buffer[_start + relative];
  int uint32At(int relative) =>
      ByteData.sublistView(_buffer).getUint32(_start + relative, Endian.little);

  Future<bool> ensure(int count) async {
    final cap = options.maxFrameBytes * 2;
    if (count > cap) {
      throw XlogResourceLimitException(
        resource: 'maxFrameBytes',
        limit: options.maxFrameBytes,
        actual: count,
        offset: offset,
      );
    }
    while (length < count) {
      if (_pending == null) {
        if (_done) return false;
        if (!await _source.moveNext()) {
          _done = true;
          return false;
        }
        final chunk = _source.current;
        if (chunk.length > options.maxInputChunkBytes) {
          throw XlogResourceLimitException(
            resource: 'maxInputChunkBytes',
            limit: options.maxInputChunkBytes,
            actual: chunk.length,
            offset: offset,
          );
        }
        inputBytes += chunk.length;
        if (chunk.isEmpty) continue;
        _pending = chunk;
        _pendingOffset = 0;
      }
      final amount = math.min(cap - length, _pending!.length - _pendingOffset);
      _reserve(length + amount);
      _buffer.setRange(_end, _end + amount, _pending!, _pendingOffset);
      _end += amount;
      _pendingOffset += amount;
      peakBufferedBytes = math.max(peakBufferedBytes, length);
      if (_pendingOffset == _pending!.length) _pending = null;
    }
    return true;
  }

  void _reserve(int capacity) {
    if (_buffer.length - _end >= capacity - length) return;
    final retained = length;
    if (_buffer.length >= capacity) {
      _buffer.setRange(0, retained, _buffer, _start);
    } else {
      final next = Uint8List(
        math.min(
          options.maxFrameBytes * 2,
          math.max(capacity, _buffer.length * 2),
        ),
      );
      next.setRange(0, retained, _buffer, _start);
      _buffer = next;
    }
    _start = 0;
    _end = retained;
  }

  void discard(int count) {
    _start += count;
    offset += count;
    if (_start == _end) _start = _end = 0;
  }

  void resetInvalid() => invalidWasAllZero = true;

  void discardInvalid() {
    // Batch bytes which cannot begin any accepted frame (notably mmap zeros),
    // avoiding an async operation per byte of garbage.
    var count = 1;
    while (count < length) {
      final value = byteAt(count);
      if (value >= 1 && value <= 13) break;
      count++;
    }
    for (var i = 0; i < count; i++) {
      if (byteAt(i) != 0) invalidWasAllZero = false;
    }
    discard(count);
  }

  Future<void> cancel() async {
    _pending = null;
    await _source.cancel();
  }
}
