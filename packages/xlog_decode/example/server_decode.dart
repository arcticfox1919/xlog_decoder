import 'dart:io';

import 'package:xlog_decode/xlog_decode.dart';

/// A file adapter for a backend worker, not an HTTP server.
///
/// Usage: dart run example/server_decode.dart input.xlog output.log
/// Provision XLOG_PRIVATE_KEY in the worker environment for encrypted logs.
/// A real service should select its key after authorizing the caller's key ID.
Future<void> main(List<String> arguments) async {
  if (arguments.length != 2) {
    stderr.writeln(
      'Usage: dart run example/server_decode.dart input.xlog output.log',
    );
    exitCode = 64;
    return;
  }
  try {
    final summary = await _decodeFile(
      File(arguments[0]).absolute,
      File(arguments[1]).absolute,
    );
    stdout.writeln(
      'Decoded ${summary.blockCount} blocks, ${summary.outputBytes} bytes.',
    );
  } on Exception catch (error) {
    stderr.writeln('Decode failed: $error');
    exitCode = 1;
  } on ArgumentError {
    // Never print the private-key value or the worker's environment.
    stderr.writeln('Invalid decoder configuration or private key.');
    exitCode = 64;
  }
}

Future<XlogStreamSummary> _decodeFile(File input, File output) async {
  Directory? temporaryDirectory;
  RandomAccessFile? openOutput;
  var reservedOutput = false;
  var committed = false;
  try {
    // Exclusive reservation rejects existing files, including the input itself.
    // Only this request's empty reservation is replaced when decoding succeeds.
    await output.create(exclusive: true);
    reservedOutput = true;
    temporaryDirectory = await output.parent.createTemp('.xlog-decode-');
    final temporaryOutput = File('${temporaryDirectory.path}/decoded.log');
    final writer = await temporaryOutput.open(mode: FileMode.writeOnly);
    openOutput = writer;
    final decoder = XlogDecoder(
      privateKeyHex: Platform.environment['XLOG_PRIVATE_KEY'],
      strict: true,
    );
    final summary = await decoder.decodeTo(
      input.openRead(),
      onData: (bytes) async {
        // Awaiting each write applies backpressure instead of filling a sink.
        await writer.writeFrom(bytes);
      },
    );
    if (summary.blockCount == 0 || summary.outputBytes == 0) {
      throw const FormatException('No log content recovered');
    }
    await writer.flush();
    await writer.close();
    openOutput = null;
    await temporaryOutput.rename(output.path);
    committed = true;
    return summary;
  } finally {
    try {
      await openOutput?.close();
    } finally {
      try {
        if (temporaryDirectory != null) {
          await temporaryDirectory.delete(recursive: true);
        }
      } finally {
        if (reservedOutput && !committed) await output.delete();
      }
    }
  }
}
