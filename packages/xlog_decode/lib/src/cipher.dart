// TEA adapted from Tencent Mars (MIT License).
// Copyright (C) 2016 THL A29 Limited, a Tencent company.
// ECDH uses PointyCastle; only Mars-specific 16-round little-endian TEA is custom.
import 'dart:convert';
import 'dart:typed_data';

import 'package:pointycastle/ecc/api.dart';
import 'package:pointycastle/ecc/curves/secp256k1.dart';

class XlogCipher {
  XlogCipher(String? privateKeyHex, {Iterable<String>? privateKeysHex})
    : _privateKeys = _parseKeys(privateKeyHex, privateKeysHex),
      automatic = privateKeysHex != null,
      _maxCachedKeys = null;
  XlogCipher._(this._privateKeys, this.automatic, this._maxCachedKeys);

  final bool automatic;
  final int? _maxCachedKeys;
  final List<BigInt> _privateKeys;
  final _keyCache = <String, Uint8List>{};
  int get candidateCount => _privateKeys.length;

  /// All candidate/private-public pairs share one per-operation LRU cache.
  XlogCipher newSession({int? maxCachedKeys}) => XlogCipher._(
    _privateKeys,
    automatic,
    maxCachedKeys ?? (automatic ? 16 : null),
  );

  Uint8List decrypt(
    Uint8List payload,
    Uint8List publicKey, {
    int candidate = 0,
  }) {
    if (_privateKeys.isEmpty) {
      throw const FormatException('Encrypted block requires privateKeyHex');
    }
    final id = '$candidate:${base64.encode(publicKey)}';
    final cached = _keyCache.remove(id);
    final key = cached ?? _deriveTeaKey(publicKey, _privateKeys[candidate]);
    if (_maxCachedKeys != 0) {
      if (_maxCachedKeys != null && _keyCache.length >= _maxCachedKeys) {
        _keyCache.remove(_keyCache.keys.first);
      }
      _keyCache[id] = key;
    }
    return _teaDecrypt(payload, key);
  }

  static List<BigInt> _parseKeys(
    String? primary,
    Iterable<String>? candidates,
  ) {
    final keys = <BigInt>{};
    final first = _parsePrivateKey(primary);
    if (first != null) keys.add(first);
    for (final candidate in candidates ?? const <String>[]) {
      final key = _parsePrivateKey(candidate);
      if (key == null) throw ArgumentError('Empty candidate private key');
      keys.add(key);
    }
    return List.unmodifiable(keys);
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

  Uint8List _deriveTeaKey(Uint8List publicKey, BigInt privateKey) {
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
      ..init(ECPrivateKey(privateKey, curve));
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
