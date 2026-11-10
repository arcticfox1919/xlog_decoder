import 'package:shelf/shelf.dart';

import '../responses.dart';

Middleware cors(Set<String> allowedOrigins) =>
    (inner) => (request) async {
      final origin = request.headers['origin'];
      final allowed =
          origin != null &&
          (allowedOrigins.contains(origin) ||
              origin == request.requestedUri.origin);
      if (request.method == 'OPTIONS' && origin != null && !allowed) {
        return errorResponse(403, 'origin_denied', 'Origin not allowed.');
      }
      final headers = <String, String>{
        if (allowed) ...{
          'Access-Control-Allow-Origin': origin,
          'Vary': 'Origin',
          'Access-Control-Allow-Headers': 'Content-Type',
          'Access-Control-Allow-Methods': 'GET, POST, DELETE, OPTIONS',
        },
      };
      if (request.method == 'OPTIONS') return Response(204, headers: headers);
      return (await inner(request)).change(headers: headers);
    };
