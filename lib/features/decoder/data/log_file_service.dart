import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;
import 'package:xlog_decode/xlog_decode.dart';

import '../domain/decode_failure.dart';
import '../domain/decode_models.dart';

abstract interface class LogFileService {
  Future<DecodeBatchResult> decode(DecodeRequest request);
}

/// File handles and ZIP contents stay inside the worker isolate.
class LocalLogFileService implements LogFileService {
  const LocalLogFileService();

  @override
  Future<DecodeBatchResult> decode(DecodeRequest request) =>
      Isolate.run(() => _decodeInput(request));
}

Future<DecodeBatchResult> _decodeInput(DecodeRequest request) async {
  final input = File(p.absolute(request.inputPath));
  if (!await input.exists()) {
    throw const DecodeFailure(DecodeErrorCode.inputMissing);
  }
  final outputDirectory = request.outputDirectory?.trim();
  final directory = Directory(
    outputDirectory == null || outputDirectory.isEmpty
        ? p.dirname(input.path)
        : outputDirectory,
  );
  final decoder = XlogDecoder(privateKeyHex: request.privateKeyHex);
  await directory.create(recursive: true);

  if (p.extension(input.path).toLowerCase() != '.zip') {
    return DecodeBatchResult([
      await _decodeLog(
        p.basename(input.path),
        await input.readAsBytes(),
        directory,
        decoder,
      ),
    ]);
  }

  final stream = InputFileStream(input.path);
  final results = <DecodedFile>[];
  Directory? zipOutput;
  var skipped = 0;
  try {
    final archive = ZipDecoder().decodeStream(stream);
    for (final entry in archive) {
      final normalized = entry.name.replaceAll('\\', '/');
      final name = p.posix.basename(normalized);
      if (!entry.isFile ||
          entry.isSymbolicLink ||
          normalized.startsWith('__MACOSX/') ||
          name.startsWith('.') ||
          ![
            '.xlog',
            '.log',
            '.bin',
          ].contains(p.posix.extension(name).toLowerCase())) {
        skipped++;
        continue;
      }
      try {
        // Decode in memory, never extract archive-provided paths to disk.
        if (entry.size > 256 * 1024 * 1024) {
          throw const DecodeFailure(DecodeErrorCode.zipEntryTooLarge);
        }
        final bytes = entry.readBytes();
        if (bytes == null) {
          throw const DecodeFailure(DecodeErrorCode.zipEntryUnreadable);
        }
        if (entry.crc32 != null && getCrc32(bytes) != entry.crc32) {
          throw const DecodeFailure(DecodeErrorCode.zipChecksumFailed);
        }
        zipOutput ??= await _reserveZipDirectory(directory, input.path);
        results.add(await _decodeLog(entry.name, bytes, zipOutput, decoder));
      } on Exception catch (error) {
        results.add(
          DecodedFile(
            sourceName: entry.name,
            error: _message(error),
            failure: error is DecodeFailure ? error : null,
          ),
        );
      } finally {
        entry.clear();
      }
    }
  } finally {
    stream.closeSync();
  }
  if (results.isEmpty) {
    throw const DecodeFailure(DecodeErrorCode.zipNoLogs);
  }
  return DecodeBatchResult(results, skippedEntries: skipped);
}

Future<DecodedFile> _decodeLog(
  String name,
  Uint8List bytes,
  Directory directory,
  XlogDecoder decoder,
) async {
  try {
    final result = decoder.decode(bytes);
    if (result.blocks.isEmpty || result.bytes.isEmpty) {
      final detail = result.issues.isEmpty ? '' : result.issues.first.message;
      throw DecodeFailure(DecodeErrorCode.noLogContent, detail: detail);
    }
    final output = await _reserveOutput(directory, name);
    try {
      await output.writeAsBytes(result.bytes, flush: true);
    } on Exception {
      await output.delete();
      rethrow;
    }
    return DecodedFile(
      sourceName: name,
      outputPath: output.path,
      byteCount: result.bytes.length,
      blockCount: result.blocks.length,
      issues: List.unmodifiable(result.issues.map((issue) => issue.toString())),
    );
  } on Exception catch (error) {
    return DecodedFile(
      sourceName: name,
      error: _message(error),
      failure: error is DecodeFailure ? error : null,
    );
  }
}

String _outputStem(String sourceName) {
  final basename = p.posix.basename(sourceName.replaceAll('\\', '/'));
  final stem = p
      .basenameWithoutExtension(basename)
      .replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
  return stem.isEmpty || stem == '.' || stem == '..' ? 'logs' : stem;
}

Future<Directory> _reserveZipDirectory(
  Directory parent,
  String sourceName,
) async {
  final stem = _outputStem(sourceName);
  for (var index = 0; ; index++) {
    final suffix = index == 0 ? '' : '$index';
    final directory = Directory(p.join(parent.absolute.path, '$stem$suffix'));
    if (await FileSystemEntity.type(directory.path, followLinks: false) !=
        FileSystemEntityType.notFound) {
      continue;
    }
    return directory.create();
  }
}

Future<File> _reserveOutput(Directory directory, String sourceName) async {
  final stem = _outputStem(sourceName);
  for (var index = 0; ; index++) {
    final suffix = index == 0 ? '' : '$index';
    final file = File(p.join(directory.absolute.path, '$stem$suffix.log'));
    try {
      return await file.create(exclusive: true);
    } on FileSystemException {
      if (await FileSystemEntity.type(file.path, followLinks: false) ==
          FileSystemEntityType.notFound) {
        rethrow;
      }
    }
  }
}

String _message(Exception error) =>
    error is FormatException ? error.message : error.toString();
