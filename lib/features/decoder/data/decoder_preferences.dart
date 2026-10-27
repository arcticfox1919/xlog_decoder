class DecoderPreferences {
  const DecoderPreferences({this.outputDirectory, this.privateKeyHex});

  final String? outputDirectory;
  final String? privateKeyHex;
}

abstract interface class DecoderPreferencesStore {
  Future<DecoderPreferences> load();
  Future<void> saveOutputDirectory(String? directory);
  Future<void> savePrivateKey(String? privateKeyHex);
}
