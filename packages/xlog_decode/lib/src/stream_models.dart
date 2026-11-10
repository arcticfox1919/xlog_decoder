/// Per-operation memory limits for the streaming decoder.
///
/// These limits bound frames, decompression, and the upstream event retained by
/// the decoder. They do not include buffers retained by the source or consumer.
class XlogStreamOptions {
  const XlogStreamOptions({
    this.maxFrameBytes = 1024 * 1024,
    this.maxDecodedBlockBytes = 4 * 1024 * 1024,
    this.maxInputChunkBytes = 1024 * 1024,
    this.outputChunkBytes = 64 * 1024,
    this.maxZstdWindowBytes = 8 * 1024 * 1024,
    this.maxCachedKeys = 16,
  });

  final int maxFrameBytes;
  final int maxDecodedBlockBytes;
  final int maxInputChunkBytes;
  final int outputChunkBytes;
  final int maxZstdWindowBytes;
  final int maxCachedKeys;

  void validate() {
    for (final entry in {
      'maxFrameBytes': maxFrameBytes,
      'maxDecodedBlockBytes': maxDecodedBlockBytes,
      'maxInputChunkBytes': maxInputChunkBytes,
      'outputChunkBytes': outputChunkBytes,
      'maxZstdWindowBytes': maxZstdWindowBytes,
    }.entries) {
      if (entry.value < 1) {
        throw ArgumentError.value(entry.value, entry.key, 'Must be > 0');
      }
    }
    if (maxCachedKeys < 0) {
      throw ArgumentError.value(maxCachedKeys, 'maxCachedKeys', 'Must be >= 0');
    }
    if (maxZstdWindowBytes > 0x80000000) {
      throw ArgumentError.value(
        maxZstdWindowBytes,
        'maxZstdWindowBytes',
        'Must be <= 2 GiB',
      );
    }
  }
}

/// A constant-size summary; block and issue details are delivered by callbacks.
class XlogStreamSummary {
  const XlogStreamSummary({
    required this.inputBytes,
    required this.outputBytes,
    required this.blockCount,
    required this.issueCount,
    required this.peakBufferedBytes,
  });

  final int inputBytes;
  final int outputBytes;
  final int blockCount;
  final int issueCount;

  /// Peak bytes retained in the frame parser, excluding the upstream chunk,
  /// decompression buffers, key cache, and output consumer. Not process RSS.
  final int peakBufferedBytes;
}

/// A fatal streaming limit violation, regardless of recovery/strict mode.
class XlogResourceLimitException implements Exception {
  const XlogResourceLimitException({
    required this.resource,
    required this.limit,
    required this.actual,
    required this.offset,
  });

  final String resource;
  final int limit;
  final int actual;
  final int offset;

  @override
  String toString() =>
      'XlogResourceLimitException: $resource exceeds $limit '
      '(requested $actual at byte $offset)';
}
