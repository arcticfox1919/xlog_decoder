// TEA adapted from Tencent Mars (MIT), Copyright (C) 2016 THL A29 Limited.
// Public deterministic TEST keys and a Mars-compatible encrypting producer.
// This helper has no file or cwd dependency and is never used by production.
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:pointycastle/ecc/curves/secp256k1.dart';

const fixturePrivateKeyA =
    '0000000000000000000000000000000000000000000000000000000000000001';
const fixturePrivateKeyB =
    '0000000000000000000000000000000000000000000000000000000000000003';
const fixtureWrongPrivateKey =
    '0000000000000000000000000000000000000000000000000000000000000007';

Uint8List encryptedFrame(
  int magic,
  String privateKeyHex, {
  List<int>? plain,
  List<int>? compressed,
  int sequence = 0,
}) {
  final content =
      plain ?? utf8.encode('[I] automatic key selection fixture\n' * 4);
  final payload = Uint8List.fromList(
    compressed ??
        (magic == 7
            ? Deflate(content).getBytes()
            : ZstdEncoder().encodeBytes(content)),
  );
  final curve = ECCurve_secp256k1();
  final point = curve.G * BigInt.two;
  final secret = (point! * BigInt.parse(privateKeyHex, radix: 16))!.x!
      .toBigInteger()!;
  final hex = secret.toRadixString(16).padLeft(64, '0');
  final key = Uint8List.fromList([
    for (var i = 0; i < 32; i++)
      int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16),
  ]);
  final keyData = ByteData.sublistView(key);
  final k = [
    for (var i = 0; i < 4; i++) keyData.getUint32(i * 4, Endian.little),
  ];
  final bytes = ByteData.sublistView(payload);
  const mask = 0xffffffff;
  for (var offset = 0; offset + 8 <= payload.length; offset += 8) {
    var first = bytes.getUint32(offset, Endian.little);
    var second = bytes.getUint32(offset + 4, Endian.little);
    var sum = 0;
    for (var round = 0; round < 16; round++) {
      sum = (sum + 0x9e3779b9) & mask;
      first =
          (first +
              (((second << 4) + k[0]) ^
                  (second + sum) ^
                  ((second >> 5) + k[1]))) &
          mask;
      second =
          (second +
              (((first << 4) + k[2]) ^ (first + sum) ^ ((first >> 5) + k[3]))) &
          mask;
    }
    bytes.setUint32(offset, first, Endian.little);
    bytes.setUint32(offset + 4, second, Endian.little);
  }
  final output = Uint8List(74 + payload.length);
  output[0] = magic;
  final header = ByteData.sublistView(output);
  header.setUint16(1, sequence, Endian.little);
  header.setUint32(5, payload.length, Endian.little);
  output.setRange(9, 73, point.getEncoded(false).sublist(1));
  output.setRange(73, 73 + payload.length, payload);
  return output;
}
