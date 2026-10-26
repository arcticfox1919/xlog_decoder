class DecodeRequest {
  const DecodeRequest({
    required this.inputPath,
    this.outputDirectory,
    this.privateKeyHex,
  });

  final String inputPath;
  final String? outputDirectory;
  final String? privateKeyHex;
}

class DecodedFile {
  const DecodedFile({
    required this.sourceName,
    this.outputPath,
    this.byteCount = 0,
    this.blockCount = 0,
    this.issues = const [],
    this.error,
  });

  final String sourceName;
  final String? outputPath;
  final int byteCount;
  final int blockCount;
  final List<String> issues;
  final String? error;
  bool get succeeded => outputPath != null;
}

class DecodeBatchResult {
  DecodeBatchResult(List<DecodedFile> files, {this.skippedEntries = 0})
    : files = List.unmodifiable(files);

  final List<DecodedFile> files;
  final int skippedEntries;
  int get successCount => files.where((file) => file.succeeded).length;
  int get failureCount => files.length - successCount;
  bool get hasWarnings =>
      failureCount > 0 || files.any((file) => file.issues.isNotEmpty);
}

enum DecodeTaskStatus { queued, running, success, warning, failure }

class DecodeTask {
  const DecodeTask({
    required this.id,
    required this.inputPath,
    this.status = DecodeTaskStatus.queued,
    this.result,
    this.error,
  });

  final int id;
  final String inputPath;
  final DecodeTaskStatus status;
  final DecodeBatchResult? result;
  final String? error;
}
