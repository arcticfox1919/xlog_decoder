import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'compression.dart';

/// Automatic candidates must consume the entire compressed frame. The legacy
/// decoder intentionally retains its historical, more permissive behavior.
Uint8List inflateCandidate(Uint8List payload, int limit) {
  if (payload.isEmpty) throw const FormatException('Empty encrypted payload');
  final flushed =
      payload.length >= 4 &&
      payload[payload.length - 4] == 0 &&
      payload[payload.length - 3] == 0 &&
      payload[payload.length - 2] == 255 &&
      payload[payload.length - 1] == 255;
  final input = InputMemoryStream(
    flushed
        ? (Uint8List(payload.length + 5)
            ..setAll(0, payload)
            ..setAll(payload.length, [1, 0, 0, 255, 255]))
        : payload,
  );
  final output = _BoundedCandidateOutput(limit);
  final inflater = Inflate.lazy(input, output: output);
  while (inflater.inflateBlock()) {
    if (input.isEOS) {
      throw const FormatException('Incomplete encrypted DEFLATE frame');
    }
  }
  if (!input.isEOS) {
    throw const FormatException('Unused encrypted DEFLATE bytes');
  }
  return output.getBytes();
}

class _BoundedCandidateOutput extends OutputMemoryStream {
  _BoundedCandidateOutput(this.limit)
    : super(size: math.min(32768, math.max(1, limit)));
  final int limit;
  void _check(int amount) {
    if (length + amount > limit) throw const XlogOutputLimitException();
  }

  @override
  void writeByte(int value) {
    _check(1);
    super.writeByte(value);
  }

  @override
  void writeBytes(List<int> bytes, {int? length}) {
    _check(length ?? bytes.length);
    super.writeBytes(bytes, length: length);
  }

  @override
  void writeStream(InputStream stream) {
    _check(stream.length);
    super.writeStream(stream);
  }

  @override
  void writeBackReference(int distance, int count) {
    _check(count);
    super.writeBackReference(distance, count);
  }
}
