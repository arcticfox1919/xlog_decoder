// TEA adapted from Tencent Mars (MIT License).
// Copyright (C) 2016 THL A29 Limited, a Tencent company.
// ECDH uses PointyCastle; only Mars-specific 16-round little-endian TEA is custom.
import 'dart:convert';
import 'dart:typed_data';

import 'package:pointycastle/ecc/api.dart';
import 'package:pointycastle/ecc/curves/secp256k1.dart';

class XlogCipher {
  XlogCipher(String? privateKeyHex)
    : _privateKey = _parsePrivateKey(privateKeyHex);
  XlogCipher._(this._privateKey);

  final BigInt? _privateKey;
  final _keyCache = <String, Uint8List>{};

  /// Reuse validated configuration, with a cache scoped to one decoded file.
  XlogCipher newSession() => XlogCipher._(_privateKey);

  Uint8List decrypt(Uint8List payload, Uint8List publicKey) {
    if (_privateKey == null) {
      throw const FormatException('Encrypted block requires privateKeyHex');
    }
    final id = base64.encode(publicKey);
    final key = _keyCache[id] ??= _deriveTeaKey(publicKey);
    return _teaDecrypt(payload, key);
  }

  static BigInt? _parsePrivateKey(String? hex) {
    if (hex == null || hex.trim().isEmpty) return null;
    hex = hex.trim();
    if (!RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(hex)) {
      throw ArgumentError('Private key must contain exactly 64 hex characters');
    }
    final key = BigInt.parse(hex, radix: 16);
    if (key <= BigInt.zero || key >= ECCurve_secp256k1().n) {
      throw ArgumentError('Private key is outside the secp256k1 scalar range');
    }
    return key;
  }

  Uint8List _deriveTeaKey(Uint8List publicKey) {
    final curve = ECCurve_secp256k1();
    final point = curve.curve.decodePoint(
      Uint8List.fromList([4, ...publicKey]),
    );
    if (point == null || point.isInfinity) {
      throw const FormatException('Invalid secp256k1 public key');
    }
    // PointyCastle's uncompressed point parser does not check curve membership.
    final x = point.x!;
    final y = point.y!;
    if (y.square() != x.square() * x + curve.curve.b!) {
      throw const FormatException('Public key is not on secp256k1');
    }
    final agreement = ECDHBasicAgreement()
      ..init(ECPrivateKey(_privateKey!, curve));
    final secret = agreement.calculateAgreement(ECPublicKey(point, curve));
    // uECC emits the X coordinate as 32 big-endian bytes, preserving zeros.
    final hex = secret.toRadixString(16).padLeft(64, '0');
    return Uint8List.fromList([
      for (var i = 0; i < 32; i++)
        int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16),
    ]);
  }
}

Uint8List _teaDecrypt(Uint8List payload, Uint8List key) {
  final result = Uint8List.fromList(payload);
  final data = ByteData.sublistView(result);
  final keyData = ByteData.sublistView(key);
  final k = [
    for (var i = 0; i < 4; i++) keyData.getUint32(i * 4, Endian.little),
  ];
  const mask = 0xffffffff;
  const delta = 0x9e3779b9;
  for (var offset = 0; offset + 8 <= payload.length; offset += 8) {
    var v0 = data.getUint32(offset, Endian.little);
    var v1 = data.getUint32(offset + 4, Endian.little);
    var sum = (delta << 4) & mask;
    for (var round = 0; round < 16; round++) {
      v1 = (v1 - (((v0 << 4) + k[2]) ^ (v0 + sum) ^ ((v0 >> 5) + k[3]))) & mask;
      v0 = (v0 - (((v1 << 4) + k[0]) ^ (v1 + sum) ^ ((v1 >> 5) + k[1]))) & mask;
      sum = (sum - delta) & mask;
    }
    data.setUint32(offset, v0, Endian.little);
    data.setUint32(offset + 4, v1, Endian.little);
  }
  // The final 0–7 bytes were never encrypted by CryptAsyncLog.
  return result;
}
