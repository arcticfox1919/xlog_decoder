class DecoderPreferences {
  const DecoderPreferences({this.outputDirectory, this.privateKeyHex});

  final String? outputDirectory;
  final String? privateKeyHex;
}

abstract interface class DecoderPreferencesStore {
  Future<DecoderPreferences> load();
  Future<String?> loadLanguageCode();
  Future<void> saveLanguageCode(String? languageCode);
  Future<void> saveOutputDirectory(String? directory);
  Future<void> savePrivateKey(String? privateKeyHex);
}
