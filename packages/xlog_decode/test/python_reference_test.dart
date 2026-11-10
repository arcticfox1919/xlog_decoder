import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:xlog_decode/src/frame.dart';
import 'package:xlog_decode/xlog_decode.dart';

import 'support/fixtures.dart';

void main() {
  final reference =
      jsonDecode(File('test/fixtures/python_reference.json').readAsStringSync())
          as Map<String, dynamic>;

  for (final value in reference['cases'] as List<dynamic>) {
    final entry = value as Map<String, dynamic>;
    test('Python DecodeBuffer: ${entry['name']}', () async {
      final decoder = XlogDecoder(
        privateKeyHex: entry['privateKey'] as String?,
        strict: true,
      );
      final input = unhex(entry['input'] as String);
      final result = decoder.decode(input);
      expect(result.bytes, unhex(entry['output'] as String));
      expect(result.issues, isEmpty);

      final streamed = BytesBuilder(copy: false);
      final issues = <XlogIssue>[];
      final summary = await decoder.decodeTo(
        _fragmented(input),
        onData: streamed.add,
        onIssue: issues.add,
      );
      expect(streamed.takeBytes(), result.bytes);
      expect(
        issues.map((issue) => issue.toString()),
        result.issues.map((issue) => issue.toString()),
      );
      expect(summary.inputBytes, input.length);
      expect(summary.outputBytes, result.bytes.length);
      expect(summary.blockCount, result.blocks.length);
      expect(summary.issueCount, result.issues.length);
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

// Cycle through tiny, differently sized pieces to split framing and compressed
// data at many offsets without relying on file-system read chunk boundaries.
Stream<List<int>> _fragmented(Uint8List bytes) async* {
  var size = 1;
  for (var offset = 0; offset < bytes.length;) {
    final end = offset + size < bytes.length ? offset + size : bytes.length;
    yield bytes.sublist(offset, end);
    offset = end;
    size = size % 17 + 1;
  }
}
