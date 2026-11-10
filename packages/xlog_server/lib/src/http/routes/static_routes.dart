import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';

import '../../application/ports/static_assets.dart';
import '../http_failure.dart';

class StaticRoutes {
  const StaticRoutes(this.files);
  final StaticAssets? files;

  Future<Response> call(Request request) async {
    if (request.method != 'GET' || files == null) {
      throw const HttpFailure(404, 'not_found', 'Not found.');
    }
    final file = await files!.read(
      request.url.path.isEmpty ? 'index.html' : request.url.path,
    );
    if (file == null) throw const HttpFailure(404, 'not_found', 'Not found.');
    const types = {
      '.html': 'text/html; charset=utf-8',
      '.css': 'text/css; charset=utf-8',
      '.js': 'application/javascript',
      '.json': 'application/json',
      '.svg': 'image/svg+xml',
      '.wasm': 'application/wasm',
    };
    return Response.ok(
      file.openRead(),
      headers: {
        'Content-Type':
            types[p.extension(file.filename)] ?? 'application/octet-stream',
        'Content-Length': '${file.length}',
      },
    );
  }
}
