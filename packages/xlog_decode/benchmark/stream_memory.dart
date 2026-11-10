import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:xlog_decode/xlog_decode.dart';

/// Generates encoded frames on demand and discards decoded output.
///
/// Run separate processes, for example with 16 and 256 MiB, to compare peak
/// process RSS. This measures the streaming path, not disk/network throughput
/// or concurrent-request scheduling. VM/JIT memory is included in process RSS.
Future<void> main(List<String> arguments) async {
  final inputMiB = arguments.isEmpty
      ? 16
      : arguments.length == 1
      ? int.tryParse(arguments.single)
      : null;
  if (inputMiB == null || inputMiB < 1) {
    stderr.writeln(
      'Usage: dart run benchmark/stream_memory.dart [positive input MiB]',
    );
    exitCode = 64;
    return;
  }
  final inputBytes = inputMiB * 1024 * 1024;
  final stopwatch = Stopwatch()..start();
  final summary = await XlogDecoder(
    maxOutputBytes: inputBytes,
    strict: true,
  ).decodeTo(_frames(inputBytes), onData: (_) {});
  stopwatch.stop();
  final seconds =
      stopwatch.elapsedMicroseconds / Duration.microsecondsPerSecond;
  stdout.writeln(
    const JsonEncoder.withIndent('  ').convert({
      'inputBytes': summary.inputBytes,
      'outputBytes': summary.outputBytes,
      'blockCount': summary.blockCount,
      'elapsedMilliseconds': stopwatch.elapsedMilliseconds,
      'inputMiBPerSecond': inputMiB / seconds,
      'peakProcessRssBytes': ProcessInfo.maxRss,
      'peakParserBufferedBytes': summary.peakBufferedBytes,
      'note':
          'Generated input; output discarded; not a disk/network benchmark.',
    }),
  );
}

Stream<List<int>> _frames(int remaining) async* {
  const payloadLength = 8192;
  const overhead = 74;
  final fullFrame = _frame(payloadLength);
  while (remaining > overhead) {
    final length = math.min(remaining - overhead, payloadLength);
    // Reuse immutable source data rather than constructing a complete file.
    yield length == payloadLength ? fullFrame : _frame(length);
    remaining -= length + overhead;
  }
  if (remaining > 0) yield Uint8List(remaining); // Mars mmap trailing padding.
}

Uint8List _frame(int payloadLength) {
  final bytes = Uint8List(73 + payloadLength + 1);
  bytes[0] = 0x08;
  ByteData.sublistView(bytes).setUint32(5, payloadLength, Endian.little);
  bytes.fillRange(73, 73 + payloadLength, 65);
  return bytes;
}
