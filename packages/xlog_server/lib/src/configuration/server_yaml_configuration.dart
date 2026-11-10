import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import 'configuration_fields.dart';
import 'server_configuration_exception.dart';

/// Reads and checks the file schema; merging and defaults belong to the loader.
class ServerYamlConfiguration {
  static const fields = {
    'host',
    'port',
    'keysFile',
    'keys',
    'dataDirectory',
    'webRoot',
    'allowedOrigins',
    'limits',
  };
  static const limitFields = {
    'maxUploadBytes',
    'maxOutputBytes',
    'maxConcurrentJobs',
    'maxQueuedJobs',
    'maxRetainedJobs',
    'jobTtlSeconds',
    'uploadTimeoutSeconds',
  };

  Future<Map<String, Object?>> read(File file) async {
    Object? document;
    late String source;
    try {
      source = await file.readAsString();
      document = loadYaml(source);
    } on FileSystemException {
      throw ServerConfigurationException('configFile', 'could not read file');
    } on YamlException {
      throw ServerConfigurationException('configFile', 'invalid YAML');
    } on FormatException {
      throw ServerConfigurationException('configFile', 'invalid text');
    }
    final values = document == null && source.trim().isEmpty
        ? <String, Object?>{}
        : configurationMap(document, 'configuration');
    knownConfigurationFields(values, fields, 'configuration');
    for (final name in ['host', 'keysFile', 'dataDirectory', 'webRoot']) {
      if (values.containsKey(name)) {
        configurationString(values[name], name, nonEmpty: true);
      }
    }
    if (values.containsKey('port') && values['port'] is! int) {
      throw ServerConfigurationException('port', 'expected an integer');
    }
    if (values.containsKey('keys') && values.containsKey('keysFile')) {
      throw ServerConfigurationException(
        'keys',
        'cannot be combined with keysFile',
      );
    }
    if (values.containsKey('keys')) configurationMap(values['keys'], 'keys');
    if (values.containsKey('allowedOrigins')) {
      final origins = values['allowedOrigins'];
      if (origins is! List) {
        throw ServerConfigurationException('allowedOrigins', 'expected a list');
      }
      values['allowedOrigins'] = [
        for (final origin in origins)
          configurationString(origin, 'allowedOrigins', nonEmpty: true),
      ];
    }
    if (values.containsKey('limits')) {
      final limits = configurationMap(values['limits'], 'limits');
      knownConfigurationFields(limits, limitFields, 'limits');
      for (final entry in limits.entries) {
        if (entry.value is! int) {
          throw ServerConfigurationException(
            'limits.${entry.key}',
            'expected an integer',
          );
        }
      }
      values['limits'] = limits;
    }
    for (final name in ['keysFile', 'dataDirectory', 'webRoot']) {
      final value = values[name];
      if (value is String) {
        values[name] = p.normalize(p.join(file.absolute.parent.path, value));
      }
    }
    return values;
  }
}
