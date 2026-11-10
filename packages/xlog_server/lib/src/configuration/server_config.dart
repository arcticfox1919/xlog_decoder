import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:xlog_decode/xlog_decode.dart';

import '../application/job_limits.dart';
import '../domain/server_key.dart';

/// Immutable deployment configuration, validated before binding a socket.
class ServerConfig {
  ServerConfig({
    required this.dataDirectory,
    Map<String, ServerKey> keys = const {},
    this.webRoot,
    int maxUploadBytes = 256 * 1024 * 1024,
    int maxOutputBytes = 128 * 1024 * 1024,
    int maxConcurrentJobs = 2,
    int maxQueuedJobs = 4,
    int maxRetainedJobs = 64,
    Duration jobTtl = const Duration(hours: 1),
    Duration uploadTimeout = const Duration(minutes: 10),
    Set<String> allowedOrigins = const {
      'http://localhost:18780',
      'http://127.0.0.1:18780',
    },
  }) : keys = Map.unmodifiable(keys),
       allowedOrigins = Set.unmodifiable(allowedOrigins),
       limits = JobLimits(
         maxUploadBytes: maxUploadBytes,
         maxOutputBytes: maxOutputBytes,
         maxConcurrentJobs: maxConcurrentJobs,
         maxQueuedJobs: maxQueuedJobs,
         maxRetainedJobs: maxRetainedJobs,
         jobTtl: jobTtl,
         uploadTimeout: uploadTimeout,
       ) {
    for (final key in this.keys.values) {
      if (key.privateKeyHex.trim().isEmpty) {
        throw ArgumentError('Empty server key');
      }
      XlogDecoder(privateKeyHex: key.privateKeyHex);
    }
    if (webRoot != null) {
      _checkSeparation(dataDirectory.absolute.path, webRoot!.absolute.path);
    }
  }

  final Directory dataDirectory;
  final Map<String, ServerKey> keys;
  final Directory? webRoot;
  final Set<String> allowedOrigins;
  final JobLimits limits;

  int get maxUploadBytes => limits.maxUploadBytes;
  int get maxOutputBytes => limits.maxOutputBytes;
  int get maxConcurrentJobs => limits.maxConcurrentJobs;
  int get maxQueuedJobs => limits.maxQueuedJobs;
  int get maxRetainedJobs => limits.maxRetainedJobs;
  Duration get jobTtl => limits.jobTtl;
  Duration get uploadTimeout => limits.uploadTimeout;

  /// Recheck actual paths to reject aliases through pre-existing symlinks.
  Future<void> validateDirectories() async {
    final web = webRoot;
    if (web == null || !await web.exists() || !await dataDirectory.exists()) {
      return;
    }
    _checkSeparation(
      await dataDirectory.resolveSymbolicLinks(),
      await web.resolveSymbolicLinks(),
    );
  }

  static void _checkSeparation(String data, String web) {
    final dataPath = p.normalize(data);
    final webPath = p.normalize(web);
    if (p.equals(dataPath, webPath) ||
        p.isWithin(webPath, dataPath) ||
        p.isWithin(dataPath, webPath)) {
      throw ArgumentError('Data and static directories must be separate');
    }
  }
}
