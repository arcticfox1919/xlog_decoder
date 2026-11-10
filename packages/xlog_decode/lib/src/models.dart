import 'dart:convert';
import 'dart:typed_data';

/// Python scripts define the default format and decoding behavior.
/// Select [c] explicitly for C-only 0x01–0x02 and 9-byte 0x03–0x05 headers.
enum XlogLegacyFormat { python, c }

enum XlogIssueKind { framing, sequence, payload }

class XlogIssue {
  const XlogIssue(this.kind, this.offset, this.message);

  final XlogIssueKind kind;
  final int offset;
  final String message;

  @override
  String toString() => '${kind.name} at byte $offset: $message';
}

class XlogDecodeException implements Exception {
  const XlogDecodeException(this.issue);
  final XlogIssue issue;

  @override
  String toString() => 'XlogDecodeException: $issue';
}

class XlogBlock {
  const XlogBlock({
    required this.offset,
    required this.magic,
    required this.sequence,
    required this.beginHour,
    required this.endHour,
    required this.payloadLength,
    required this.decodedLength,
  });

  final int offset;
  final int magic;
  final int sequence;
  final int beginHour;
  final int endHour;
  final int payloadLength;
  final int decodedLength;
}

class XlogDecodeResult {
  XlogDecodeResult(this.bytes, List<XlogBlock> blocks, List<XlogIssue> issues)
    : blocks = List.unmodifiable(blocks),
      issues = List.unmodifiable(issues);

  /// Exact log bytes; diagnostics are kept separately in [issues].
  final Uint8List bytes;
  final List<XlogBlock> blocks;
  final List<XlogIssue> issues;

  String get text => utf8.decode(bytes, allowMalformed: true);
}
