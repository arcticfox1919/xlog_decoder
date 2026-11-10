import 'package:shelf/shelf.dart';

import '../application/job_service.dart';
import '../application/ports/static_assets.dart';
import 'middleware/cors.dart';
import 'middleware/error_handling.dart';
import 'middleware/security_headers.dart';
import 'middleware/request_logging.dart';
import 'routes/job_routes.dart';
import 'routes/static_routes.dart';

Handler createServerHandler({
  required JobService jobs,
  required Set<String> allowedOrigins,
  required StaticAssets? staticFiles,
}) {
  final router = JobRoutes(jobs).router
    ..all('/<path|.*>', StaticRoutes(staticFiles).call);
  return const Pipeline()
      .addMiddleware(requestLogging())
      .addMiddleware(securityHeaders())
      .addMiddleware(cors(allowedOrigins))
      .addMiddleware(errorHandling())
      .addHandler(router.call);
}
