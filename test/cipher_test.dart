import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:xlog_decoder/core/xlog/cipher.dart';

import 'support/fixtures.dart';

void main() {
  final publicKey = unhex(reference['publicKey'] as String);
  final privateKey = reference['privateKey'] as String;

  group('Original C TEA vectors', () {
    final vectors = reference['tea'] as List<dynamic>;
    for (var i = 0; i < vectors.length; i++) {
      test('${i + 8} bytes: whole blocks and unchanged remainder', () {
        final vector = vectors[i] as Map<String, dynamic>;
        final encrypted = unhex(vector['cipher'] as String);
        final original = Uint8List.fromList(encrypted);
        final cipher = XlogCipher(privateKey);
        expect(
          cipher.decrypt(encrypted, publicKey),
          unhex(vector['plain'] as String),
        );
        expect(encrypted, original, reason: 'Input must not be mutated');
        expect(
          cipher.decrypt(encrypted, publicKey),
          unhex(vector['plain'] as String),
        );
      });
    }

    test('ECDH preserves the leading zero of the shared secret', () {
      final vector = reference['leadingZero'] as Map<String, dynamic>;
      expect(
        XlogCipher(privateKey).decrypt(
          unhex(vector['cipher'] as String),
          unhex(vector['publicKey'] as String),
        ),
        unhex(vector['plain'] as String),
      );
    });
  });

  test('Missing private key is explicit', () {
    expect(
      () => XlogCipher(null).decrypt(Uint8List(8), publicKey),
      throwsFormatException,
    );
  });

  test('Rejects a point outside the curve', () {
    expect(
      () => XlogCipher(privateKey).decrypt(Uint8List(8), Uint8List(64)),
      throwsFormatException,
    );
  });

  for (final invalid in ['xyz', '0' * 64, 'f' * 64]) {
    test('Rejects invalid private key ${invalid.substring(0, 3)}', () {
      expect(() => XlogCipher(invalid), throwsArgumentError);
    });
  }
}
