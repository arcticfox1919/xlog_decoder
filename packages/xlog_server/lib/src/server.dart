import 'dart:async';
import 'dart:io';

import 'package:shelf/shelf.dart' as shelf;
import 'package:logging/logging.dart';

import 'package:shelf/shelf_io.dart' as shelf_io;

import 'application/job_service.dart';
import 'application/ports/job_executor.dart';
import 'application/ports/job_storage.dart';
import 'configuration/server_config.dart';
import 'http/server_handler.dart';
import 'infrastructure/execution/isolate_job_executor.dart';
import 'infrastructure/storage/file_job_storage.dart';
import 'infrastructure/storage/static_file_store.dart';

/// Composition root and network lifecycle; business rules live in JobService.
class XlogServer {
  XlogServer._(this.config, this._jobs, this.handler);

  final ServerConfig config;
  final JobService _jobs;
  final shelf.Handler handler;
  HttpServer? _server;
  Timer? _cleanup;
  Future<void>? _closing;

  int get port => _boundServer.port;
  InternetAddress get address => _boundServer.address;
  HttpServer get _boundServer =>
      _server ?? (throw StateError('Server is not bound'));

  /// Builds the same production pipeline without opening a listening socket.
  static Future<XlogServer> create(
    ServerConfig config, {
    JobStorage? storage,
    JobExecutor? executor,
    DateTime Function()? clock,
    String Function()? idFactory,
  }) async {
    final files = storage ?? FileJobStorage(config.dataDirectory);
    await files.initialize();
    await config.validateDirectories();
    final jobs = JobService(
      storage: files,
      executor: executor ?? const IsolateJobExecutor(),
      limits: config.limits,
      keys: config.keys,
      clock: clock,
      idFactory: idFactory,
    );
    return XlogServer._(
      config,
      jobs,
      createServerHandler(
        jobs: jobs,
        allowedOrigins: config.allowedOrigins,
        staticFiles: config.webRoot == null
            ? null
            : StaticFileStore(
                config.webRoot!,
                privateDirectory: config.dataDirectory,
              ),
      ),
    );
  }

  static Future<XlogServer> bind(
    ServerConfig config, {
    String host = '127.0.0.1',
    int port = 18781,
  }) async {
    final app = await create(config);
    try {
      app._server = await shelf_io.serve(
        app.handler,
        host,
        port,
        poweredByHeader: null,
      );
      app._cleanup = Timer.periodic(const Duration(minutes: 1), (_) {
        unawaited(app._jobs.expire());
      });
      Logger('xlog.server').info({
        'event': 'server.started',
        'message':
            'Xlog API listening on http://${app.address.address}:${app.port}',
      });
      return app;
    } catch (_) {
      await app.close();
      rethrow;
    }
  }

  Future<void> close() => _closing ??= _close();

  Future<void> _close() async {
    Logger('xlog.server').info({'event': 'server.stopping'});
    _cleanup?.cancel();
    // Stop admission and queue progression before any asynchronous socket work.
    final jobsClosing = _jobs.close();
    await Future.wait<void>([
      jobsClosing,
      if (_server != null) _server!.close(force: true).then<void>((_) {}),
    ]);
    Logger('xlog.server').info({'event': 'server.stopped'});
  }
}
