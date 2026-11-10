import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../../application/job_service.dart';
import '../responses.dart';
import '../serialization/job_json.dart';

/// HTTP translation only: scheduling and storage belong to JobService ports.
class JobRoutes {
  const JobRoutes(this.jobs);
  final JobService jobs;

  Router get router {
    final routes = Router()
      ..get('/api/health', _health)
      ..post('/api/jobs', _upload)
      ..get('/api/jobs/<id>/download', _download)
      ..get('/api/jobs/<id>', _get)
      ..delete('/api/jobs/<id>', _delete);
    for (final path in [
      '/api/health',
      '/api/jobs',
      '/api/jobs/<id>',
      '/api/jobs/<id>/download',
    ]) {
      routes.all(
        path,
        (Request _) =>
            errorResponse(405, 'method_not_allowed', 'Method not allowed.'),
      );
    }
    routes
      ..all('/api', _notFound)
      ..all('/api/<path|.*>', _notFound);
    return routes;
  }

  Future<Response> _health(Request request) async {
    await jobs.expire();
    return jsonResponse(200, {
      'status': 'ok',
      'maxUploadBytes': jobs.limits.maxUploadBytes,
      'maxConcurrentJobs': jobs.limits.maxConcurrentJobs,
      'maxQueuedJobs': jobs.limits.maxQueuedJobs,
      'supportsZip': true,
    });
  }

  Future<Response> _upload(Request request) async => jsonResponse(
    202,
    jobJson(
      await jobs.submit(
        request.url.queryParameters['filename'] ?? '',
        request.read(),
        contentLength: request.contentLength,
      ),
    ),
  );

  Future<Response> _get(Request request, String id) async =>
      jsonResponse(200, jobJson(await jobs.get(id)));

  Future<Response> _delete(Request request, String id) async =>
      jsonResponse(200, jobJson(await jobs.delete(id)));

  Future<Response> _download(Request request, String id) async {
    final file = await jobs.download(id);
    return Response.ok(
      file.openRead(),
      headers: {
        'Content-Type': file.filename.endsWith('.zip')
            ? 'application/zip'
            : 'application/octet-stream',
        'Content-Disposition': _attachment(file.filename),
        'Content-Length': '${file.length}',
      },
      context: const {'shelf.io.buffer_output': false},
    );
  }

  Response _notFound(Request request) =>
      errorResponse(404, 'not_found', 'API endpoint not found.');
}

// Keep an ASCII fallback for older clients and preserve the original Unicode
// filename using the standard UTF-8 extended parameter.
String _attachment(String filename) {
  final fallback = filename.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
  final basic = 'attachment; filename="$fallback"';
  if (filename == fallback) return basic;
  final encoded = Uri.encodeComponent(filename).replaceAll("'", '%27');
  return "$basic; filename*=UTF-8''$encoded";
}
