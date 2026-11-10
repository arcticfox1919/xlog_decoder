import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;
import 'package:xlog_decode/xlog_decode.dart';

import '../../domain/decode_result.dart';
import '../../domain/decode_task.dart';
import 'limited_file_output.dart';
import 'log_file_decoder.dart';
import 'output_filename.dart';
import 'zip_directory_validator.dart';
import 'zip_limits.dart';

/// Decodes eligible members one at a time using two reusable temporary files.
class ZipJobDecoder {
  const ZipJobDecoder({this.limits = const ZipLimits()});

  final ZipLimits limits;

  Future<DecodeResult> decode(DecodeTask task) async {
    final input = File(p.join(task.workspacePath, 'input'));
    ZipDirectoryValidator(limits: limits).validate(input);
    final stream = InputFileStream(input.path, bufferSize: 64 * 1024);
    final output = File(p.join(task.workspacePath, 'decoded.zip'));
    var complete = false;
    try {
      // Reject links before ZipDecoder can materialize their target strings.
      final directory = ZipDirectory()..read(stream);
      if (directory.fileHeaders.length > limits.maxEntries ||
          directory.fileHeaders.any(
            (header) =>
                ((header.externalFileAttributes >> 16) & 0xf000) == 0xa000,
          )) {
        throw const FormatException(
          'ZIP links or excessive entries unsupported',
        );
      }
      final archive = ZipDecoder().decodeStream(stream, throwOnError: true);
      if (archive.length > limits.maxEntries) {
        throw const FormatException('Too many ZIP entries');
      }
      final encoder = ZipFileEncoder();
      encoder.create(output.path, level: ZipFileEncoder.store);
      var expanded = 0;
      var outputBytes = 0;
      var blocks = 0;
      var issues = 0;
      var decodedCount = 0;
      try {
        for (final entry in archive) {
          final normalized = entry.name.replaceAll('\\', '/');
          final basename = p.posix.basename(normalized);
          if (!_eligible(entry, normalized, basename)) continue;
          final extracted = File(p.join(task.workspacePath, 'entry.input'));
          final decoded = File(p.join(task.workspacePath, 'entry.log'));
          try {
            final remainingExpansion = limits.maxExpandedBytes - expanded;
            if (entry.size > limits.maxEntryBytes ||
                entry.size > remainingExpansion ||
                remainingExpansion <= 0) {
              throw const FormatException('ZIP expansion limit exceeded');
            }
            final extraction = LimitedFileOutput(
              extracted.path,
              remainingExpansion < limits.maxEntryBytes
                  ? remainingExpansion
                  : limits.maxEntryBytes,
            );
            try {
              entry.writeContent(extraction);
            } finally {
              extraction.closeSync();
            }
            expanded += extraction.length;
            if (entry.crc32 != null && extraction.crc != entry.crc32) {
              throw const FormatException('ZIP checksum failed');
            }
            final remaining = task.maxOutputBytes - outputBytes;
            if (remaining < 1) {
              throw XlogResourceLimitException(
                resource: 'maxOutputBytes',
                limit: task.maxOutputBytes,
                actual: outputBytes + 1,
                offset: 0,
              );
            }
            XlogStreamSummary summary;
            try {
              summary = await const LogFileDecoder().decode(
                input: extracted,
                output: decoded,
                maxOutputBytes: remaining,
                privateKeysHex: task.privateKeysHex,
              );
            } on XlogKeySelectionException {
              rethrow;
            } on FormatException {
              issues++;
              continue;
            } on XlogDecodeException {
              issues++;
              continue;
            }
            outputBytes += summary.outputBytes;
            blocks += summary.blockCount;
            issues += summary.issueCount;
            decodedCount++;
            _addDecodedFile(
              encoder,
              decoded,
              '${decodedCount}_${outputStem(basename)}.log',
            );
          } finally {
            entry.clear();
            try {
              if (await extracted.exists()) await extracted.delete();
            } finally {
              if (await decoded.exists()) await decoded.delete();
            }
          }
        }
      } finally {
        await encoder.close();
      }
      if (decodedCount == 0) throw const FormatException('No logs recovered');
      complete = true;
      return DecodeResult(
        filename: 'decoded.zip',
        outputBytes: outputBytes,
        blockCount: blocks,
        issueCount: issues,
      );
    } finally {
      try {
        stream.closeSync();
      } finally {
        if (!complete && await output.exists()) await output.delete();
      }
    }
  }

  void _addDecodedFile(ZipFileEncoder encoder, File file, String name) {
    final stream = InputFileStream(file.path, bufferSize: 64 * 1024);
    try {
      final entry = ArchiveFile.stream(name, stream)
        ..compression = CompressionType.none;
      encoder.addArchiveFile(entry);
    } finally {
      // ZipFileEncoder.addFile does not close its input when encoding throws.
      stream.closeSync();
    }
  }

  bool _eligible(ArchiveFile entry, String normalized, String basename) =>
      entry.isFile &&
      !entry.isSymbolicLink &&
      !normalized.startsWith('__MACOSX/') &&
      !basename.startsWith('.') &&
      const [
        '.xlog',
        '.log',
        '.bin',
      ].contains(p.extension(basename).toLowerCase());
}
