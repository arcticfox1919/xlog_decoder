import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'hive_preferences_store.dart';

HivePreferencesStore createPreferencesStore() => HivePreferencesStore(
  directoryProvider: () async =>
      p.join((await getApplicationSupportDirectory()).path, 'settings'),
  keyStore: const SystemEncryptionKeyStore(),
);

class SystemEncryptionKeyStore implements EncryptionKeyStore {
  const SystemEncryptionKeyStore();

  // The login keychain works for a locally signed macOS app without requiring
  // Keychain Sharing entitlements or re-enabling the application sandbox.
  static const _storage = FlutterSecureStorage(
    mOptions: MacOsOptions(usesDataProtectionKeychain: false),
  );
  static const _key = 'xlog_decoder.preferences.aes_key.v1';

  @override
  Future<String?> read() => _storage.read(key: _key);

  @override
  Future<void> write(String key) => _storage.write(key: _key, value: key);
}
