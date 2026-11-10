import 'package:xlog_decoder/features/decoder/data/decoder_preferences.dart';

class FakePreferencesStore implements DecoderPreferencesStore {
  String? languageCode;
  String? directory;

  @override
  Future<String?> loadLanguageCode() async => languageCode;

  @override
  Future<void> saveLanguageCode(String? value) async => languageCode = value;
  String? privateKey;

  @override
  Future<DecoderPreferences> load() async =>
      DecoderPreferences(outputDirectory: directory, privateKeyHex: privateKey);

  @override
  Future<void> saveOutputDirectory(String? value) async => directory = value;

  @override
  Future<void> savePrivateKey(String? value) async => privateKey = value;
}
