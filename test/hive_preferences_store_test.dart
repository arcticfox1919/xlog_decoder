import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:path/path.dart' as p;
import 'package:xlog_decoder/features/decoder/data/hive_preferences_store.dart';

class MemoryEncryptionKeyStore implements EncryptionKeyStore {
  String? value;
  int reads = 0;

  @override
  Future<String?> read() async {
    reads++;
    return value;
  }

  @override
  Future<void> write(String key) async => value = key;
}

void main() {
  late Directory directory;
  late MemoryEncryptionKeyStore keys;
  HivePreferencesStore store() => HivePreferencesStore(
    directoryProvider: () async => directory.path,
    keyStore: keys,
  );

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('xlog-settings-');
    keys = MemoryEncryptionKeyStore();
  });
  tearDown(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });

  test(
    'directory survives reopening without accessing secure storage',
    () async {
      await store().saveOutputDirectory('/output/logs');
      await Hive.close();
      final loaded = await store().load();
      expect(loaded.outputDirectory, '/output/logs');
      expect(loaded.privateKeyHex, isNull);
      expect(keys.reads, 0);
      await store().saveOutputDirectory(null);
      await Hive.close();
      expect((await store().load()).outputDirectory, isNull);
    },
  );

  test(
    'private key survives reopening and never appears in Hive files',
    () async {
      final privateKey = '0' * 63 + '1';
      await store().savePrivateKey(privateKey);
      expect(base64Url.decode(keys.value!), hasLength(32));
      await Hive.close();
      for (final file in directory.listSync().whereType<File>()) {
        final contents = latin1.decode(await file.readAsBytes());
        expect(contents.contains(privateKey), isFalse);
        expect(contents.contains(keys.value!), isFalse);
      }
      expect((await store().load()).privateKeyHex, privateKey);
      await store().savePrivateKey('');
      await Hive.close();
      expect((await store().load()).privateKeyHex, isNull);
    },
  );

  test('missing system key preserves existing encrypted data', () async {
    await store().savePrivateKey('0' * 63 + '1');
    await Hive.close();
    final file = File(p.join(directory.path, 'private_key.hive'));
    final before = await file.readAsBytes();
    keys.value = null;
    await expectLater(store().load(), throwsStateError);
    expect(keys.value, isNull);
    expect(await file.readAsBytes(), before);
  });

  test('clearing an unused private key creates no secret box', () async {
    await store().savePrivateKey('');
    expect(keys.reads, 0);
    expect(await Hive.boxExists('private_key', path: directory.path), isFalse);
  });
}
