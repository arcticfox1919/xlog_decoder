import 'package:xlog_decoder/features/decoder/data/decoder_preferences.dart';

class FakePreferencesStore implements DecoderPreferencesStore {
  String? directory;
  String? privateKey;

  @override
  Future<DecoderPreferences> load() async =>
      DecoderPreferences(outputDirectory: directory, privateKeyHex: privateKey);

  @override
  Future<void> saveOutputDirectory(String? value) async => directory = value;

  @override
  Future<void> savePrivateKey(String? value) async => privateKey = value;
}
