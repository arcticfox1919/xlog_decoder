import 'dart:io';

import 'package:xlog_decode/xlog_decode.dart';

/// Streams decoded bytes to disk; each write completes before decoding resumes.
class LogFileDecoder {
  const LogFileDecoder();

  Future<XlogStreamSummary> decode({
    required File input,
    required File output,
    required int maxOutputBytes,
    Iterable<String> privateKeysHex = const [],
  }) async {
    final decoder = XlogDecoder(
      privateKeysHex: privateKeysHex,
      maxOutputBytes: maxOutputBytes,
    );
    final writer = await output.open(mode: FileMode.writeOnly);
    try {
      try {
        final summary = await decoder.decodeTo(
          input.openRead(),
          onData: (bytes) async {
            await writer.writeFrom(bytes);
          },
        );
        if (summary.blockCount == 0 || summary.outputBytes == 0) {
          throw const FormatException('No log content');
        }
        return summary;
      } finally {
        await writer.close();
      }
    } catch (_) {
      if (await output.exists()) await output.delete();
      rethrow;
    }
  }
}
