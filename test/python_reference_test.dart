import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:xlog_decoder/core/xlog/frame.dart';
import 'package:xlog_decoder/xlog_decoder.dart';

import 'support/fixtures.dart';

void main() {
  final reference =
      jsonDecode(File('test/fixtures/python_reference.json').readAsStringSync())
          as Map<String, dynamic>;

  for (final value in reference['cases'] as List<dynamic>) {
    final entry = value as Map<String, dynamic>;
    test('Python DecodeBuffer: ${entry['name']}', () {
      final result = XlogDecoder(
        privateKeyHex: entry['privateKey'] as String?,
        strict: true,
      ).decode(unhex(entry['input'] as String));
      expect(result.bytes, unhex(entry['output'] as String));
      expect(result.issues, isEmpty);
    });
  }

  for (final value in reference['starts'] as List<dynamic>) {
    final entry = value as Map<String, dynamic>;
    test('Python GetLogStartPos: ${entry['name']}', () {
      final input = unhex(entry['input'] as String);
      final offset = const XlogFrameReader(XlogLegacyFormat.python).findStart(
        input,
        ByteData.sublistView(input),
        count: entry['count'] as int,
      );
      expect(offset ?? -1, entry['offset']);
    });
  }

  test('Python default rejects C-only magic 0x01 and 0x02', () {
    for (final magic in [1, 2]) {
      final result = XlogDecoder().decode(frame(magic, [65]));
      expect(result.blocks, isEmpty);
      expect(result.issues.single.kind, XlogIssueKind.framing);
    }
  });

  test('Initial search skips an isolated candidate before a valid start', () {
    final result = XlogDecoder().decode(
      Uint8List.fromList([
        ...frame(8, [65]),
        255,
        ...frame(8, [66]),
      ]),
    );
    expect(result.bytes, [66]);
    expect(result.blocks.single.offset, frame(8, [65]).length + 1);
  });
}
