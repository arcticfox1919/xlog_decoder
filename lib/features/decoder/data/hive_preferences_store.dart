import 'dart:convert';

import 'package:hive/hive.dart';

import 'decoder_preferences.dart';

abstract interface class EncryptionKeyStore {
  Future<String?> read();
  Future<void> write(String key);
}

/// Only the directory is stored in plain text. The private key lives in a
/// separate AES-256 encrypted box; its random key is kept in the OS key store.
class HivePreferencesStore implements DecoderPreferencesStore {
  HivePreferencesStore({
    required Future<String> Function() directoryProvider,
    required EncryptionKeyStore keyStore,
  }) : _directoryProvider = directoryProvider,
       _keyStore = keyStore;

  final Future<String> Function() _directoryProvider;
  final EncryptionKeyStore _keyStore;
  Future<String>? _directory;
  Future<Box<String>>? _preferences;
  Future<Box<String>>? _secrets;

  Future<String> get _path => _directory ??= _directoryProvider();

  Future<Box<String>> _openPreferences() => _preferences ??= () async {
    return Hive.openBox<String>('preferences', path: await _path);
  }();

  Future<bool> _hasSecrets() async =>
      Hive.boxExists('private_key', path: await _path);

  Future<Box<String>> _openSecrets() => _secrets ??= () async {
    final exists = await _hasSecrets();
    var encodedKey = await _keyStore.read();
    if (encodedKey == null) {
      if (exists) {
        // Never replace an existing encrypted box with a new, unrelated key.
        throw StateError('无法读取本机加密密钥，已保留原有私钥数据。');
      }
      encodedKey = base64UrlEncode(Hive.generateSecureKey());
      await _keyStore.write(encodedKey);
      if (await _keyStore.read() != encodedKey) {
        throw StateError('无法保存本机加密密钥，未保存私钥。');
      }
    }
    final key = base64Url.decode(encodedKey);
    if (key.length != 32) throw const FormatException('本机加密密钥无效。');
    return Hive.openBox<String>(
      'private_key',
      path: await _path,
      encryptionCipher: HiveAesCipher(key),
    );
  }();

  @override
  Future<DecoderPreferences> load() async {
    final preferences = await _openPreferences();
    final secrets = await _hasSecrets() ? await _openSecrets() : null;
    return DecoderPreferences(
      outputDirectory: preferences.get('outputDirectory'),
      privateKeyHex: secrets?.get('privateKeyHex'),
    );
  }

  @override
  Future<void> saveOutputDirectory(String? directory) async {
    final preferences = await _openPreferences();
    if (directory == null || directory.trim().isEmpty) {
      await preferences.delete('outputDirectory');
    } else {
      await preferences.put('outputDirectory', directory);
    }
  }

  @override
  Future<void> savePrivateKey(String? privateKeyHex) async {
    final value = privateKeyHex?.trim();
    if (value == null || value.isEmpty) {
      if (_secrets != null || await _hasSecrets()) {
        await (await _openSecrets()).delete('privateKeyHex');
      }
    } else {
      await (await _openSecrets()).put('privateKeyHex', value);
    }
  }
}
