import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xlog_decoder/xlog_decoder.dart';

import 'support/fixtures.dart';

void main() {
  final expected = unhex(reference['plain'] as String);

  test('Decodes finished zstd frames and concatenated frames', () {
    final compressed = ZstdEncoder().encodeBytes(expected);
    final result = XlogDecoder(
      strict: true,
    ).decode(frame(13, [...compressed, ...compressed]));
    expect(result.bytes, [...expected, ...expected]);
  });

  test('Rejects empty, invalid and truncated zstd blocks', () {
    final validPayload = modern('0d').sublist(73, modern('0d').length - 1);
    for (final payload in [
      <int>[],
      [255],
      validPayload.sublist(0, 5),
      validPayload.sublist(0, validPayload.length - 1),
    ]) {
      final result = XlogDecoder().decode(frame(13, payload));
      expect(result.bytes, isEmpty);
      expect(result.issues.single.kind, XlogIssueKind.payload);
    }
  });

  test('Does not turn a truncated zstd checksum into a valid frame', () {
    // A checksum flag is set on a complete last raw block; checksum is absent.
    final result = XlogDecoder().decode(
      frame(13, [0x28, 0xb5, 0x2f, 0xfd, 0x24, 1, 9, 0, 0, 65]),
    );
    expect(result.issues.single.kind, XlogIssueKind.payload);
  });

  test('Rejects malformed deflate instead of returning partial success', () {
    for (final payload in [
      [255],
      [1, 2, 3],
    ]) {
      expect(
        XlogDecoder().decode(frame(9, payload)).issues.single.kind,
        XlogIssueKind.payload,
      );
    }
  });

  test('Empty deflate payload follows Python decompressobj behavior', () {
    final result = XlogDecoder(strict: true).decode(frame(9, []));
    expect(result.bytes, isEmpty);
    expect(result.blocks, hasLength(1));
    expect(result.issues, isEmpty);
  });

  test('Decodes finished raw DEFLATE with the Dart implementation', () {
    final result = XlogDecoder(
      strict: true,
    ).decode(frame(9, Deflate(expected).getBytes()));
    expect(result.bytes, expected);
  });

  test('Byte views with nonzero buffer offsets are supported', () {
    final input = modern('09');
    final storage = Uint8List(input.length + 10)
      ..setRange(5, input.length + 5, input);
    expect(
      XlogDecoder(
        strict: true,
      ).decode(Uint8List.sublistView(storage, 5, input.length + 5)).bytes,
      expected,
    );
  });
}
