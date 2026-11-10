import 'package:shelf/shelf.dart';

Middleware securityHeaders() =>
    (inner) => (request) async {
      final response = await inner(request);
      return response.change(
        headers: const {
          'X-Content-Type-Options': 'nosniff',
          'Cache-Control': 'no-store',
        },
      );
    };
