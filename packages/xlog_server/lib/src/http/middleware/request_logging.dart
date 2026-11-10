import 'dart:math';

import 'package:logging/logging.dart';
import 'package:shelf/shelf.dart';

final _log = Logger('xlog.http');
final _requestPrefix = Random.secure().nextInt(1 << 32).toRadixString(16);
var _nextRequest = 0;

Middleware requestLogging() =>
    (inner) => (request) async {
      final id = '$_requestPrefix-${_nextRequest++}';
      final watch = Stopwatch()..start();
      final response = await inner(
        request.change(context: {'xlog.requestId': id}),
      );
      final status = response.statusCode;
      // Health checks, polling and static assets are quiet at the default level.
      final level = status >= 500
          ? Level.SEVERE
          : status >= 400
          ? Level.WARNING
          : request.method == 'GET' && !request.url.path.endsWith('/download')
          ? Level.FINE
          : Level.INFO;
      _log.log(level, {
        'event': 'http.response',
        'requestId': id,
        'method': request.method,
        'path': '/${request.url.path}',
        'status': status,
        'responseMs': watch.elapsedMilliseconds,
      });
      return response.change(headers: {'X-Request-ID': id});
    };
