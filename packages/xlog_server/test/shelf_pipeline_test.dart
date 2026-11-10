import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart' as shelf;
import 'package:test/test.dart';
import 'package:xlog_server/xlog_server.dart';

final _fixtures =
    jsonDecode(
          File(
            '../xlog_decode/test/fixtures/mars_reference.json',
          ).readAsStringSync(),
        )
        as Map<String, dynamic>;

List<int> _unhex(String value) => [
  for (var i = 0; i < value.length; i += 2)
    int.parse(value.substring(i, i + 2), radix: 16),
];

void main() {
  late Directory temporary;
  late XlogServer server;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('xlog-shelf-test-');
    server = await XlogServer.bind(
      ServerConfig(
        dataDirectory: temporary,
        keys: {
          'mars': ServerKey('Mars test', _fixtures['privateKey'] as String),
        },
      ),
      port: 0,
    );
  });

  tearDown(() async {
    await server.close();
    if (await temporary.exists()) await temporary.delete(recursive: true);
  });

  Future<shelf.Response> request(
    String method,
    String path, {
    Map<String, String> headers = const {},
    Object? body,
  }) async => server.handler(
    shelf.Request(
      method,
      Uri.parse('http://127.0.0.1:${server.port}$path'),
      headers: {...headers},
      body: body,
    ),
  );

  Future<Map<String, dynamic>> object(shelf.Response response) async =>
      jsonDecode(await response.readAsString()) as Map<String, dynamic>;

  void expectSecurityHeaders(shelf.Response response) {
    expect(response.headers['x-content-type-options'], 'nosniff');
    expect(response.headers['cache-control'], 'no-store');
  }

  Future<void> expectError(
    shelf.Response response,
    int status,
    String code,
  ) async {
    expect(response.statusCode, status);
    expect(response.headers['content-type'], startsWith('application/json'));
    expectSecurityHeaders(response);
    final error = (await object(response))['error'] as Map<String, dynamic>;
    expect(error['code'], code);
    expect(error['message'], isNotEmpty);
  }

  Future<Map<String, dynamic>> waitJob(String id) async {
    for (var i = 0; i < 200; i++) {
      final response = await request('GET', '/api/jobs/$id');
      expect(response.statusCode, 200);
      final job = await object(response);
      if (['success', 'warning', 'failure'].contains(job['status'])) return job;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    throw StateError('Job did not finish');
  }

  test('allowed preflight includes CORS headers for binary uploads', () async {
    final response = await request(
      'OPTIONS',
      '/api/jobs',
      headers: {
        'origin': 'http://localhost:18780',
        'access-control-request-method': 'POST',
        'access-control-request-headers': 'content-type',
      },
    );

    expect(response.statusCode, 204);
    expect(
      response.headers['access-control-allow-origin'],
      'http://localhost:18780',
    );
    expect(response.headers['vary'], contains('Origin'));
    expect(
      response.headers['access-control-allow-headers']?.toLowerCase(),
      'content-type',
    );
    expect(
      response.headers['access-control-allow-methods'],
      allOf(
        contains('GET'),
        contains('POST'),
        contains('DELETE'),
        contains('OPTIONS'),
      ),
    );
    expectSecurityHeaders(response);
    expect(await response.readAsString(), isEmpty);
  });

  test(
    'disallowed preflight returns an error without CORS permission',
    () async {
      final response = await request(
        'OPTIONS',
        '/api/jobs',
        headers: {'origin': 'https://untrusted.example'},
      );

      await expectError(response, 403, 'origin_denied');
      expect(
        response.headers.keys.where(
          (name) => name.startsWith('access-control-'),
        ),
        isEmpty,
      );
    },
  );

  test(
    'OPTIONS without an Origin remains available without CORS headers',
    () async {
      final response = await request('OPTIONS', '/api/jobs');
      expect(response.statusCode, 204);
      expect(response.headers['access-control-allow-origin'], isNull);
      expect(response.headers['access-control-allow-headers'], isNull);
      expect(await response.readAsString(), isEmpty);
    },
  );

  for (final (description, origin) in [
    ('HTTPS same-host reverse proxy', 'https://logs.example'),
    ('unlisted cross-origin client', 'https://other.example'),
  ]) {
    test(
      '$description can call GET and POST without CORS permission',
      () async {
        final headers = {
          'origin': origin,
          'content-type': 'application/octet-stream',
          // Untrusted proxy headers must not grant a CORS exception.
          'x-forwarded-proto': 'https',
          'x-forwarded-host': Uri.parse(origin).host,
          'forwarded': 'proto=https;host=${Uri.parse(origin).host}',
        };
        final health = await server.handler(
          shelf.Request(
            'GET',
            Uri.parse('http://logs.example/api/health'),
            headers: headers,
          ),
        );
        expect(health.statusCode, 200);
        expect((await object(health))['status'], 'ok');
        expectSecurityHeaders(health);
        expect(
          health.headers.keys.where(
            (name) => name.startsWith('access-control-'),
          ),
          isEmpty,
        );

        final uploaded = await server.handler(
          shelf.Request(
            'POST',
            Uri.parse('http://logs.example/api/jobs?filename=proxy.xlog'),
            headers: headers,
            body: _unhex(_fixtures['modern']['09'] as String),
          ),
        );
        expect(uploaded.statusCode, 202);
        expectSecurityHeaders(uploaded);
        expect(
          uploaded.headers.keys.where(
            (name) => name.startsWith('access-control-'),
          ),
          isEmpty,
        );
        final accepted = await object(uploaded);
        expect((await waitJob(accepted['id'] as String))['status'], 'success');
      },
    );
  }

  test('open API consumes binary uploads without credentials', () async {
    var listens = 0;
    Stream<List<int>> body() async* {
      listens++;
      yield _unhex(_fixtures['modern']['09'] as String);
    }

    final response = await request(
      'POST',
      '/api/jobs?filename=open.xlog',
      headers: {
        'content-type': 'application/octet-stream',
        'origin': 'http://localhost:18780',
      },
      body: body(),
    ).timeout(const Duration(seconds: 2));

    expect(response.statusCode, 202);
    expect(
      response.headers['access-control-allow-origin'],
      'http://localhost:18780',
    );
    expect(listens, 1);
    final accepted = await object(response);
    final job = await waitJob(accepted['id'] as String);
    expect(job['status'], 'success');
    expect(job['downloadUrl'], '/api/jobs/${job['id']}/download');
  });

  test('unknown API routes return JSON with security headers', () async {
    await expectError(
      await request('GET', '/api/does-not-exist'),
      404,
      'not_found',
    );
  });

  test(
    'unsupported methods on known routes return JSON with security headers',
    () async {
      await expectError(
        await request('POST', '/api/health'),
        405,
        'method_not_allowed',
      );
    },
  );

  for (final filename in ['streamed.xlog', '设备 日志.xlog']) {
    test('binary download preserves the original filename: $filename', () async {
      final input = _unhex(_fixtures['modern']['07'] as String);
      final expected = _unhex(_fixtures['plain'] as String);
      final uploaded = await request(
        'POST',
        '/api/jobs?filename=${Uri.encodeComponent(filename)}',
        headers: {
          'content-type': 'application/octet-stream',
          'content-length': '${input.length}',
        },
        body: Stream<List<int>>.fromIterable([
          input.sublist(0, 3),
          input.sublist(3, 17),
          input.sublist(17),
        ]),
      );

      expect(uploaded.statusCode, 202);
      expectSecurityHeaders(uploaded);
      final accepted = await object(uploaded);
      final job = await waitJob(accepted['id'] as String);
      expect(job['status'], 'success');
      expect(job['outputBytes'], expected.length);
      expect(job['downloadUrl'], '/api/jobs/${job['id']}/download');

      final downloaded = await request('GET', job['downloadUrl'] as String);
      expect(downloaded.statusCode, 200);
      expect(downloaded.headers['content-length'], '${expected.length}');
      expect(
        downloaded.headers['content-disposition'],
        filename == 'streamed.xlog'
            ? 'attachment; filename="streamed-decode.log"'
            : "attachment; filename=\"_____-decode.log\"; filename*=UTF-8''${Uri.encodeComponent('设备 日志-decode.log')}",
      );
      expectSecurityHeaders(downloaded);
      final bytes = await downloaded.read().fold<List<int>>(
        [],
        (all, chunk) => all..addAll(chunk),
      );
      expect(bytes, expected);
    });
  }
}
