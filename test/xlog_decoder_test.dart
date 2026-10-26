import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xlog_decoder/xlog_decoder.dart';

import 'support/fixtures.dart';

void main() {
  final key = reference['privateKey'] as String;
  final expected = unhex(reference['plain'] as String);

  for (final magic in ['06', '07', '08', '09', '0a', '0b', '0c', '0d']) {
    test('Matches C fixture 0x$magic byte for byte', () {
      final input = modern(magic);
      final original = Uint8List.fromList(input);
      final result = XlogDecoder(
        privateKeyHex: key,
        strict: true,
      ).decode(input);
      expect(result.bytes, expected);
      expect(result.text, contains('中文'));
      expect(result.blocks.single.beginHour, 9);
      expect(result.blocks.single.endHour, 10);
      expect(result.issues, isEmpty);
      expect(input, original);
    });
  }

  test('Synchronous crypt markers need no private key', () {
    for (final magic in ['06', '0a']) {
      expect(XlogDecoder(strict: true).decode(modern(magic)).bytes, expected);
    }
  });

  test('Combines different block formats', () {
    final input = Uint8List.fromList([
      for (final magic in ['08', '07', '0d', '0c']) ...modern(magic),
    ]);
    final result = XlogDecoder(privateKeyHex: key).decode(input);
    expect(result.bytes, [for (var i = 0; i < 4; i++) ...expected]);
    expect(result.blocks, hasLength(4));
    expect(result.issues, isEmpty);
  });

  test(
    'Recovers valid blocks after garbage, damaged payload and truncation',
    () {
      final result = XlogDecoder().decode(
        Uint8List.fromList([
          0xff,
          0xfe,
          ...frame(8, [65]),
          ...frame(9, [0xff]),
          ...frame(8, [66]),
          ...modern('09').sublist(0, 20),
        ]),
      );
      expect(result.bytes, [65, 66]);
      expect(result.issues.map((issue) => issue.kind), [
        XlogIssueKind.framing,
        XlogIssueKind.payload,
        XlogIssueKind.framing,
      ]);
    },
  );

  test('Strict mode fails on framing or payload issues', () {
    for (final input in [
      Uint8List.fromList([255]),
      frame(9, [255]),
    ]) {
      expect(
        () => XlogDecoder(strict: true).decode(input),
        throwsA(isA<XlogDecodeException>()),
      );
    }
  });

  test('Missing/wrong keys report failures and recover the next block', () {
    for (final privateKey in [null, '0' * 63 + '3']) {
      final result = XlogDecoder(privateKeyHex: privateKey).decode(
        Uint8List.fromList([
          ...modern('07'),
          ...frame(8, [65]),
        ]),
      );
      expect(result.bytes, [65]);
      expect(result.issues.single.kind, XlogIssueKind.payload);
    }
  });

  test('Sequence gaps, rollover, sync blocks and per-file reset', () {
    final decoder = XlogDecoder();
    final result = decoder.decode(
      Uint8List.fromList([
        ...frame(8, [65], sequence: 65535),
        ...frame(8, [], sequence: 0),
        ...frame(8, [66], sequence: 1),
        ...frame(8, [67], sequence: 3),
      ]),
    );
    expect(result.bytes, [65, 66, 67]);
    expect(result.issues.single.kind, XlogIssueKind.sequence);
    expect(decoder.decode(frame(8, [65], sequence: 40)).issues, isEmpty);
  });

  test('Trailing mmap padding and zero-length records', () {
    final result = XlogDecoder(strict: true).decode(
      Uint8List.fromList([
        ...frame(8, []),
        ...frame(8, []),
        ...List.filled(20, 0),
      ]),
    );
    expect(result.blocks, hasLength(2));
    expect(result.bytes, isEmpty);
  });

  test('Combined output limit applies to raw, zlib, and zstd', () {
    for (final magic in ['08', '09', '0d']) {
      final result = XlogDecoder(
        maxOutputBytes: expected.length - 1,
      ).decode(modern(magic));
      expect(result.bytes, isEmpty);
      expect(result.issues.single.kind, XlogIssueKind.payload);
    }
    expect(
      XlogDecoder(maxOutputBytes: 2)
          .decode(
            Uint8List.fromList([
              ...frame(8, [65, 66]),
              ...frame(8, [67]),
            ]),
          )
          .bytes,
      [65, 66],
    );
  });

  test('Empty input and invalid configuration', () {
    expect(XlogDecoder().decode(Uint8List(0)).blocks, isEmpty);
    expect(() => XlogDecoder(maxOutputBytes: 0), throwsArgumentError);
  });

  group('Legacy Python formats', () {
    for (final magic in [3, 4, 5]) {
      test('Magic 0x${magic.toRadixString(16)}', () {
        var payload = magic == 3 ? expected : Deflate(expected).getBytes();
        if (magic == 5) payload = chunks(payload);
        expect(
          XlogDecoder(strict: true).decode(frame(magic, payload)).bytes,
          expected,
        );
      });
    }
    test('Rejects truncated chunk lengths and content', () {
      for (final payload in [
        [1],
        [2, 0, 1],
      ]) {
        expect(
          XlogDecoder().decode(frame(5, payload)).issues.single.kind,
          XlogIssueKind.payload,
        );
      }
    });
  });

  group('Legacy C formats', () {
    for (var magic = 1; magic <= 5; magic++) {
      test('Magic 0x${magic.toRadixString(16)}', () {
        const seq = 33;
        var payload = magic == 1 || magic == 3
            ? expected
            : Deflate(expected).getBytes();
        final xorKey =
            0xcc ^ ((magic <= 2 ? payload.length : seq) & 255) ^ magic;
        payload = Uint8List.fromList([
          for (final byte in payload) byte ^ xorKey,
        ]);
        if (magic == 5) payload = chunks(payload);
        final result =
            XlogDecoder(legacyFormat: XlogLegacyFormat.c, strict: true).decode(
              frame(
                magic,
                payload,
                sequence: seq,
                headerSize: magic <= 2 ? 5 : 9,
              ),
            );
        expect(result.bytes, expected);
      });
    }
  });
}

Uint8List chunks(Uint8List input) {
  final split = input.length ~/ 2;
  return Uint8List.fromList([
    split & 255,
    split >> 8,
    ...input.sublist(0, split),
    (input.length - split) & 255,
    (input.length - split) >> 8,
    ...input.sublist(split),
  ]);
}
