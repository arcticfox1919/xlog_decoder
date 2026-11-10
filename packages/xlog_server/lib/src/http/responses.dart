import 'dart:convert';

import 'package:shelf/shelf.dart';

Response jsonResponse(int status, Object value) => Response(
  status,
  body: jsonEncode(value),
  headers: const {'Content-Type': 'application/json; charset=utf-8'},
);

Response errorResponse(int status, String code, String message) =>
    jsonResponse(status, {
      'error': {'code': code, 'message': message},
    }).change(headers: const {'Connection': 'close'});
