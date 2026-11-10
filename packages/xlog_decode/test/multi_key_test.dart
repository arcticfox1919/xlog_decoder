import 'dart:async';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:test/test.dart';
import 'package:xlog_decode/src/cipher.dart';
import 'package:xlog_decode/src/frame.dart';
import 'package:xlog_decode/src/payload_decoder.dart';
import 'package:xlog_decode/xlog_decode.dart';

import 'support/encrypted_fixture_builder.dart';
import 'support/fixtures.dart';

void main() {
  final expected = unhex(reference['plain'] as String);
  final originalKey = reference['privateKey'] as String;
  final keys = [
    fixtureWrongPrivateKey,
    originalKey,
    fixturePrivateKeyA,
    fixturePrivateKeyB,
  ];

  Future<(Uint8List, XlogStreamSummary)> stream(
    XlogDecoder decoder,
    Uint8List input, {
    XlogStreamOptions options = const XlogStreamOptions(),
  }) async {
    final output = BytesBuilder(copy: false);
    final summary = await decoder.decodeTo(
      Stream.fromIterable([
        for (var offset = 0; offset < input.length; offset += 17)
          input.sublist(
            offset,
            offset + 17 < input.length ? offset + 17 : input.length,
          ),
      ]),
      onData: output.add,
      options: options,
    );
    return (output.takeBytes(), summary);
  }

  for (final magic in ['07', '0c']) {
    test('auto selects a later key for original C fixture $magic', () async {
      final decoder = XlogDecoder(privateKeysHex: keys);
      expect(decoder.decode(modern(magic)).bytes, expected);
      final result = await stream(decoder, modern(magic));
      expect(result.$1, expected);
      expect(result.$2.blockCount, 1);
      expect(result.$2.issueCount, 0);
    });
  }
  for (final magic in ['09', '0d']) {
    test(
      'auto accepts plain compressed fixture $magic without any key',
      () async {
        final result = await stream(
          XlogDecoder(privateKeysHex: []),
          modern(magic),
        );
        expect(result.$1, expected);
        expect(result.$2.issueCount, 0);
      },
    );
  }

  for (final magic in [7, 12]) {
    test(
      'valid empty encrypted $magic frame precedes nonempty content',
      () async {
        final input = Uint8List.fromList([
          ...encryptedFrame(magic, fixturePrivateKeyA, plain: const []),
          ...encryptedFrame(magic, fixturePrivateKeyA, plain: expected),
        ]);
        final decoder = XlogDecoder(
          privateKeysHex: [fixtureWrongPrivateKey, fixturePrivateKeyA],
        );
        final decoded = decoder.decode(input);
        expect(decoded.bytes, expected);
        expect(decoded.blocks, hasLength(2));
        expect(decoded.blocks.first.decodedLength, 0);
        final result = await stream(decoder, input);
        expect(result.$1, expected);
        expect(result.$2.blockCount, 2);
        expect(result.$2.issueCount, 0);
      },
    );
  }

  test(
    'one stream mixes plain, encrypted formats and rotating server keys',
    () async {
      final input = Uint8List.fromList([
        ...modern('09'),
        ...encryptedFrame(7, fixturePrivateKeyA, plain: expected),
        ...encryptedFrame(12, fixturePrivateKeyB, plain: expected),
        ...modern('0d'),
        ...modern('07'),
      ]);
      final decoder = XlogDecoder(privateKeysHex: keys);
      final output = await stream(
        decoder,
        input,
        options: const XlogStreamOptions(maxCachedKeys: 1),
      );
      expect(output.$1, [for (var i = 0; i < 5; i++) ...expected]);
      expect(output.$2.blockCount, 5);
      expect(output.$2.issueCount, 0);
      expect(decoder.decode(input).bytes, output.$1);
    },
  );

  test(
    'normalizes duplicates and snapshots a mutable candidate collection',
    () async {
      final candidates = [
        originalKey,
        originalKey.toUpperCase(),
        ' $originalKey ',
      ];
      final decoder = XlogDecoder(privateKeysHex: candidates);
      candidates.clear();
      expect((await stream(decoder, modern('07'))).$1, expected);
      final combined = XlogDecoder(
        privateKeyHex: originalKey,
        privateKeysHex: [fixtureWrongPrivateKey],
      );
      expect(combined.decode(modern('0c')).bytes, expected);
    },
  );

  for (final magic in ['07', '0c']) {
    for (final candidates in <List<String>>[
      [],
      [fixtureWrongPrivateKey],
    ]) {
      test(
        'encrypted $magic cannot silently recover with ${candidates.isEmpty ? 'missing' : 'wrong'} keys',
        () async {
          final decoder = XlogDecoder(privateKeysHex: candidates);
          final matcher = isA<XlogKeySelectionException>().having(
            (error) => error.reason,
            'reason',
            candidates.isEmpty
                ? XlogKeySelectionFailure.missingKeys
                : XlogKeySelectionFailure.noMatchingKey,
          );
          expect(() => decoder.decode(modern(magic)), throwsA(matcher));
          await expectLater(stream(decoder, modern(magic)), throwsA(matcher));
        },
      );
    }
  }

  test(
    'mixed plain output cannot turn an unrecognized encrypted frame into success',
    () async {
      final input = Uint8List.fromList([...modern('09'), ...modern('07')]);
      final output = BytesBuilder();
      await expectLater(
        XlogDecoder(
          privateKeysHex: [],
        ).decodeTo(Stream.value(input), onData: output.add),
        throwsA(isA<XlogKeySelectionException>()),
      );
      expect(
        output.takeBytes(),
        expected,
        reason:
            'Caller must discard already written output after a fatal error.',
      );
    },
  );

  for (final magic in [7, 12]) {
    test(
      'output limit for encrypted $magic stays fatal even with more candidates',
      () async {
        final input = encryptedFrame(
          magic,
          fixturePrivateKeyA,
          plain: expected,
        );
        await expectLater(
          stream(
            XlogDecoder(
              privateKeysHex: [fixturePrivateKeyA, fixturePrivateKeyB],
              maxOutputBytes: expected.length - 1,
            ),
            input,
          ),
          throwsA(
            isA<XlogResourceLimitException>().having(
              (error) => error.resource,
              'resource',
              'maxOutputBytes',
            ),
          ),
        );
      },
    );
  }

  test('rotating keys share the total output budget across frames', () async {
    final input = Uint8List.fromList([
      ...encryptedFrame(7, fixturePrivateKeyA, plain: expected),
      ...encryptedFrame(12, fixturePrivateKeyB, plain: expected),
    ]);
    await expectLater(
      stream(
        XlogDecoder(
          privateKeysHex: [fixturePrivateKeyA, fixturePrivateKeyB],
          maxOutputBytes: expected.length * 2 - 1,
        ),
        input,
      ),
      throwsA(isA<XlogResourceLimitException>()),
    );
  });

  test(
    'automatic Zstandard window violation is fatal rather than another key attempt',
    () async {
      final input = encryptedFrame(
        12,
        fixturePrivateKeyA,
        compressed: [0x28, 0xb5, 0x2f, 0xfd, 0, 8, 9, 0, 0, 65],
      );
      await expectLater(
        stream(
          XlogDecoder(privateKeysHex: [fixturePrivateKeyA, fixturePrivateKeyB]),
          input,
          options: const XlogStreamOptions(maxZstdWindowBytes: 1024),
        ),
        throwsA(
          isA<XlogResourceLimitException>().having(
            (error) => error.resource,
            'resource',
            'maxZstdWindowBytes',
          ),
        ),
      );
    },
  );

  test('automatic candidate rejects unused or truncated DEFLATE data', () {
    final compressed = Deflate(expected).getBytes();
    for (final bytes in [
      <int>[...compressed, 0, 0, 0, 0, 0, 0, 0, 0],
      compressed.sublist(0, compressed.length - 2),
    ]) {
      final input = encryptedFrame(7, fixturePrivateKeyA, compressed: bytes);
      expect(
        () => XlogDecoder(privateKeysHex: [fixturePrivateKeyA]).decode(input),
        throwsA(isA<XlogKeySelectionException>()),
      );
    }
  });

  test('automatic decoding preserves output backpressure', () async {
    final input = encryptedFrame(7, fixturePrivateKeyA, plain: expected);
    final first = Completer<void>();
    final release = Completer<void>();
    var callbacks = 0;
    final operation = XlogDecoder(privateKeysHex: [fixturePrivateKeyA])
        .decodeTo(
          Stream.value(input),
          onData: (_) async {
            callbacks++;
            if (callbacks == 1) {
              first.complete();
              await release.future;
            }
          },
          options: const XlogStreamOptions(outputChunkBytes: 16),
        );
    await first.future;
    expect(callbacks, 1);
    release.complete();
    expect((await operation).outputBytes, expected.length);
  });

  test(
    'different valid candidate contents fail instead of choosing by key order',
    () {
      final input = encryptedFrame(7, fixturePrivateKeyA);
      final header = const XlogFrameReader(
        XlogLegacyFormat.python,
      ).tryRead(input, ByteData.sublistView(input), 0)!;
      final decoder = XlogPayloadDecoder(
        _AmbiguousCipher(),
        XlogLegacyFormat.python,
      );
      expect(
        () => decoder.decode(header, maxOutputBytes: 100),
        throwsA(
          isA<XlogKeySelectionException>().having(
            (error) => error.reason,
            'reason',
            XlogKeySelectionFailure.ambiguousKeys,
          ),
        ),
      );
    },
  );
}

class _AmbiguousCipher extends XlogCipher {
  _AmbiguousCipher()
    : super(null, privateKeysHex: [fixturePrivateKeyA, fixturePrivateKeyB]);
  @override
  Uint8List decrypt(
    Uint8List payload,
    Uint8List publicKey, {
    int candidate = 0,
  }) => Uint8List.fromList(Deflate([65 + candidate]).getBytes());
}
