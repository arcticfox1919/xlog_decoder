import 'dart:convert';
import 'dart:io';

import 'package:xlog_decode/xlog_decode.dart';

import '../domain/server_key.dart';
import 'configuration_fields.dart';
import 'server_configuration_exception.dart';

class ServerKeysReader {
  Future<Map<String, ServerKey>> read(File file) async {
    Object? source;
    try {
      source = jsonDecode(await file.readAsString());
    } on FileSystemException {
      throw ServerConfigurationException('keysFile', 'could not read file');
    } on FormatException {
      throw ServerConfigurationException('keysFile', 'invalid JSON');
    }
    return parse(source);
  }

  Map<String, ServerKey> parse(Object? source) {
    final keys = configurationMap(source, 'keys');
    return {
      for (final entry in keys.entries) entry.key: _key(entry.key, entry.value),
    };
  }

  ServerKey _key(String id, Object? source) {
    final values = configurationMap(source, 'keys');
    knownConfigurationFields(values, {'label', 'privateKeyHex'}, 'keys');
    final label = values.containsKey('label')
        ? configurationString(values['label'], 'keys.label')
        : id;
    final privateKey = configurationString(
      values['privateKeyHex'],
      'keys.privateKeyHex',
    );
    try {
      if (privateKey.trim().isEmpty) throw const FormatException();
      XlogDecoder(privateKeyHex: privateKey);
    } catch (_) {
      throw ServerConfigurationException(
        'keys.privateKeyHex',
        'invalid private key',
      );
    }
    return ServerKey(label, privateKey);
  }
}
