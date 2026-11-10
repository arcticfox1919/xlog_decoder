import 'dart:io';

import '../domain/server_key.dart';
import 'configuration_fields.dart';
import 'configuration_values.dart';
import 'private_configuration_file.dart';
import 'server_config.dart';
import 'server_configuration_exception.dart';
import 'server_keys_reader.dart';
import 'server_options.dart';
import 'server_yaml_configuration.dart';

/// Loads explicit file input, then applies environment overrides and defaults.
class ServerEnvironment {
  const ServerEnvironment();

  Future<ServerOptions> load(
    Map<String, String> environment, {
    String? configPath,
  }) async {
    final path = configPath ?? environment['XLOG_CONFIG_FILE'];
    final file = path == null
        ? null
        : File(configurationString(path, 'configFile', nonEmpty: true));
    final yaml = file == null
        ? <String, Object?>{}
        : await ServerYamlConfiguration().read(file);
    final values = ConfigurationValues(environment, yaml);
    final host = values.string('HOST', 'host', fallback: '127.0.0.1')!;
    final port = values.integer(
      'PORT',
      'port',
      18781,
      minimum: 0,
      maximum: 65535,
    );
    final webPath = environment['XLOG_WEB_ROOT']?.trim().isEmpty == true
        ? null
        : values.string('XLOG_WEB_ROOT', 'webRoot');
    final web = webPath == null ? null : Directory(webPath);
    if (file != null) {
      await rejectPublicConfigurationFile(file, web, 'configFile');
    }
    final keysPath = values.string('XLOG_KEYS_FILE', 'keysFile');
    final keysReader = ServerKeysReader();
    final Map<String, ServerKey> keys;
    if (keysPath != null) {
      final keyFile = File(keysPath);
      await rejectPublicConfigurationFile(keyFile, web, 'keysFile');
      keys = await keysReader.read(keyFile);
    } else {
      keys = keysReader.parse(yaml['keys'] ?? <String, Object?>{});
    }
    final maxUpload = values.limit(
      'XLOG_MAX_UPLOAD_BYTES',
      'maxUploadBytes',
      256 * 1024 * 1024,
    );
    final maxOutput = values.limit(
      'XLOG_MAX_OUTPUT_BYTES',
      'maxOutputBytes',
      128 * 1024 * 1024,
    );
    final concurrent = values.limit('XLOG_CONCURRENCY', 'maxConcurrentJobs', 2);
    final queued = values.limit(
      'XLOG_MAX_QUEUED',
      'maxQueuedJobs',
      4,
      minimum: 0,
    );
    final retained = values.limit(
      'XLOG_MAX_JOBS',
      'maxRetainedJobs',
      64,
      minimum: concurrent + queued,
    );
    final ttl = values.seconds('XLOG_JOB_TTL_SECONDS', 'jobTtlSeconds', 3600);
    final uploadTimeout = values.seconds(
      'XLOG_UPLOAD_TIMEOUT_SECONDS',
      'uploadTimeoutSeconds',
      600,
    );
    final dataPath = values.string('XLOG_DATA_DIR', 'dataDirectory');
    final ownsDirectory = dataPath == null;
    Directory data;
    try {
      data = ownsDirectory
          ? await Directory.systemTemp.createTemp('xlog-server-')
          : Directory(dataPath);
    } on FileSystemException {
      throw ServerConfigurationException(
        'dataDirectory',
        'could not create temporary directory',
      );
    }
    try {
      ServerConfig config;
      try {
        config = ServerConfig(
          dataDirectory: data,
          keys: keys,
          webRoot: web,
          maxUploadBytes: maxUpload,
          maxOutputBytes: maxOutput,
          maxConcurrentJobs: concurrent,
          maxQueuedJobs: queued,
          maxRetainedJobs: retained,
          jobTtl: ttl,
          uploadTimeout: uploadTimeout,
          allowedOrigins: values.origins,
        );
        await config.validateDirectories();
      } on ServerConfigurationException {
        rethrow;
      } on ArgumentError {
        throw ServerConfigurationException(
          'dataDirectory',
          'must be separate from webRoot',
        );
      } on FileSystemException {
        throw ServerConfigurationException(
          'dataDirectory',
          'could not validate directories',
        );
      }
      return ServerOptions(host: host, port: port, config: config);
    } catch (_) {
      if (ownsDirectory) {
        try {
          await data.delete();
        } on FileSystemException {
          // Keep the original field diagnostic if cleanup also fails.
        }
      }
      rethrow;
    }
  }
}
