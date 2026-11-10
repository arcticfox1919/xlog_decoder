import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../../../scripts/src/dev_gateway.dart';

void main() {
  late HttpServer backend;
  late HttpServer frontend;
  late DevGateway gateway;
  late HttpClient client;
  late Future<void> Function(HttpRequest) handleBackend;
  late Future<void> Function(HttpRequest) handleFrontend;

  setUp(() async {
    backend = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    frontend = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    handleBackend = (request) async {
      request.response.write('backend:${request.uri}');
      await request.response.close();
    };
    handleFrontend = (request) async {
      request.response.write('frontend:${request.uri}');
      await request.response.close();
    };
    backend.listen((request) => unawaited(handleBackend(request)));
    frontend.listen((request) => unawaited(handleFrontend(request)));
    gateway = await DevGateway.bind(
      port: 0,
      backend: Uri.parse('http://127.0.0.1:${backend.port}'),
      frontend: Uri.parse('http://127.0.0.1:${frontend.port}'),
    );
    client = HttpClient();
  });
  tearDown(() async {
    client.close(force: true);
    await gateway.close();
    await backend.close(force: true);
    await frontend.close(force: true);
  });

  Uri url(String path) => Uri.parse('http://127.0.0.1:${gateway.port}$path');
  Future<HttpClientResponse> get(String path) async =>
      (await client.getUrl(url(path))).close();

  test(
    'routes exact API paths and preserves encoded query and status',
    () async {
      handleBackend = (request) async {
        expect(request.uri.queryParameters['name'], 'one two&three');
        request.response
          ..statusCode = 429
          ..headers.set('x-upstream', 'backend')
          ..write(request.uri.path);
        await request.response.close();
      };
      for (final path in ['/api', '/api/jobs']) {
        final response = await get('$path?name=one%20two%26three');
        expect(response.statusCode, 429);
        expect(response.headers.value('x-upstream'), 'backend');
        expect(await utf8.decoder.bind(response).join(), path);
      }
      for (final path in ['/', '/styles.css', '/api-like', '/nested/page']) {
        final response = await get(path);
        expect(await utf8.decoder.bind(response).join(), 'frontend:$path');
      }
    },
  );

  test(
    'preserves the public Host and Origin for same-origin backend CORS',
    () async {
      handleBackend = (request) async {
        expect(request.headers.value('host'), '127.0.0.1:${gateway.port}');
        expect(request.headers.value('origin'), url('/').origin);
        expect(request.headers.value('x-remove'), isNull);
        request.response.headers.set('connection', 'x-internal');
        request.response.headers.set('x-internal', 'remove');
        await request.response.close();
      };
      final outgoing = await client.getUrl(url('/api/health'));
      outgoing.headers
        ..set('origin', url('/').origin)
        ..set('connection', 'x-remove')
        ..set('x-remove', 'remove');
      final response = await outgoing.close();
      expect(response.statusCode, 200);
      expect(response.headers.value('x-internal'), isNull);
      await response.drain<void>();
    },
  );

  test(
    'streams upload chunks upstream before the upload has completed',
    () async {
      final firstChunk = Completer<void>();
      final bytes = <int>[];
      handleBackend = (request) async {
        await for (final chunk in request) {
          bytes.addAll(chunk);
          if (!firstChunk.isCompleted) firstChunk.complete();
        }
        request.response
          ..statusCode = 202
          ..write('${bytes.length}');
        await request.response.close();
      };
      final outgoing = await client.postUrl(
        url('/api/jobs?filename=stream.xlog'),
      );
      outgoing.bufferOutput = false;
      outgoing.add([1, 2, 3]);
      await outgoing.flush();
      await firstChunk.future.timeout(const Duration(seconds: 3));
      expect(bytes, [1, 2, 3]);
      outgoing.add([4, 5]);
      final response = await outgoing.close();
      expect(response.statusCode, 202);
      expect(await utf8.decoder.bind(response).join(), '5');
      expect(bytes, [1, 2, 3, 4, 5]);
    },
  );

  test(
    'forwards a small fixed-length API body already buffered with its headers',
    () async {
      handleBackend = (request) async {
        expect(request.contentLength, 5);
        final body = await request.fold<List<int>>(
          [],
          (all, chunk) => all..addAll(chunk),
        );
        expect(body, [1, 2, 3, 4, 5]);
        request.response
          ..statusCode = 202
          ..write('{"accepted":true}');
        await request.response.close();
      };
      final outgoing = await client.postUrl(
        url('/api/jobs?filename=small.xlog'),
      );
      outgoing.contentLength = 5;
      outgoing.add([1, 2, 3, 4, 5]);
      final response = await outgoing.close();
      expect(response.statusCode, 202);
      expect(await utf8.decoder.bind(response).join(), '{"accepted":true}');
    },
  );

  test(
    'browser upload disconnect closes the upstream upload connection',
    () async {
      final received = Completer<void>();
      final disconnected = Completer<void>();
      handleBackend = (request) async {
        try {
          await for (final _ in request) {
            if (!received.isCompleted) received.complete();
          }
        } on IOException {
          disconnected.complete();
        } finally {
          try {
            await request.response.close();
          } on IOException {
            // The proxy intentionally aborted this upstream connection.
          }
        }
      };
      final outgoing = await client.postUrl(
        url('/api/jobs?filename=held.xlog'),
      );
      outgoing.bufferOutput = false;
      final completed = outgoing.done.then<void>(
        (_) {},
        onError: (Object _) {},
      );
      outgoing.add([1, 2, 3]);
      await outgoing.flush();
      await received.future.timeout(const Duration(seconds: 3));
      outgoing.abort(const HttpException('Test browser disconnected'));
      await completed;
      await disconnected.future.timeout(const Duration(seconds: 3));
    },
  );

  test(
    'streams SSE/download output before the upstream response completes',
    () async {
      final finish = Completer<void>();
      addTearDown(() {
        if (!finish.isCompleted) finish.complete();
      });
      handleFrontend = (request) async {
        request.response
          ..bufferOutput = false
          ..headers.contentType = ContentType('text', 'event-stream')
          ..write('data: ready\n\n');
        await request.response.flush();
        await finish.future;
        request.response.write('data: complete\n\n');
        await request.response.close();
      };
      final response = await get('/events');
      expect(response.headers.contentType!.mimeType, 'text/event-stream');
      final stream = StreamIterator(response);
      expect(
        await stream.moveNext().timeout(const Duration(seconds: 3)),
        isTrue,
      );
      expect(utf8.decode(stream.current), 'data: ready\n\n');
      finish.complete();
      final remaining = <int>[];
      while (await stream.moveNext()) {
        remaining.addAll(stream.current);
      }
      expect(utf8.decode(remaining), 'data: complete\n\n');
    },
  );

  test(
    'forwards binary downloads and their content length without decompression',
    () async {
      final content = List<int>.generate(65536, (index) => index % 256);
      handleBackend = (request) async {
        request.response
          ..headers.contentType = ContentType.binary
          ..headers.contentLength = content.length
          ..headers.set(
            'content-disposition',
            'attachment; filename="decoded.zip"',
          )
          ..add(content);
        await request.response.close();
      };
      final response = await get('/api/jobs/id/download');
      expect(response.contentLength, content.length);
      expect(
        response.headers.value('content-disposition'),
        contains('decoded.zip'),
      );
      expect(
        await response.fold<List<int>>([], (all, chunk) => all..addAll(chunk)),
        content,
      );
    },
  );

  test(
    'rewrites injected hot reload URLs across streamed bootstrap chunks',
    () async {
      final finish = Completer<void>();
      addTearDown(() {
        if (!finish.isCompleted) finish.complete();
      });
      final prefix = '// development bootstrap\n' * 8;
      final oldOrigin = 'http://localhost:${frontend.port}/';
      final script =
          '$prefix$oldOrigin\$dwdsSseHandler; ws://localhost:${frontend.port}/reload; 🎯';
      handleFrontend = (request) async {
        expect(request.headers.value('accept-encoding'), 'identity');
        request.response
          ..bufferOutput = false
          ..headers.contentLength = utf8.encode(script).length
          ..headers.set('etag', 'internal-bootstrap');
        request.response.add(utf8.encode('${prefix}http://local'));
        await request.response.flush();
        await finish.future;
        request.response.add(
          utf8.encode(script.substring(prefix.length + 'http://local'.length)),
        );
        await request.response.close();
      };
      final response = await get('/main.dart.bootstrap.js');
      expect(response.contentLength, -1);
      expect(response.headers.value('etag'), isNull);
      final chunks = StreamIterator(response);
      expect(
        await chunks.moveNext().timeout(const Duration(seconds: 3)),
        isTrue,
      );
      final body = <int>[...chunks.current];
      finish.complete();
      while (await chunks.moveNext()) {
        body.addAll(chunks.current);
      }
      final expected = script
          .replaceAll(oldOrigin, '${url('/').origin}/')
          .replaceAll(
            'ws://localhost:${frontend.port}/',
            'ws://127.0.0.1:${gateway.port}/',
          );
      expect(utf8.decode(body), expected);
    },
  );

  test(
    'forwards WebSocket text, binary messages, query and subprotocol',
    () async {
      handleFrontend = (request) async {
        expect(request.uri.queryParameters['session'], 'one two');
        final socket = await WebSocketTransformer.upgrade(
          request,
          protocolSelector: (_) => 'reload',
        );
        socket.listen(socket.add);
      };
      final socket = await WebSocket.connect(
        url('/hot-reload?session=one%20two').replace(scheme: 'ws').toString(),
        protocols: ['reload'],
      );
      addTearDown(socket.close);
      expect(socket.protocol, 'reload');
      final messages = StreamIterator(socket);
      socket.add('reload');
      expect(
        await messages.moveNext().timeout(const Duration(seconds: 3)),
        isTrue,
      );
      expect(messages.current, 'reload');
      socket.add([1, 3, 5]);
      expect(
        await messages.moveNext().timeout(const Duration(seconds: 3)),
        isTrue,
      );
      expect(messages.current, [1, 3, 5]);
      await gateway.close().timeout(const Duration(seconds: 3));
      expect(await messages.moveNext(), isFalse);
    },
  );

  test(
    'returns bad gateway for an unavailable upstream and keeps serving',
    () async {
      await frontend.close(force: true);
      final failed = await get('/');
      expect(failed.statusCode, 502);
      await failed.drain<void>();
      final working = await get('/api/health');
      expect(working.statusCode, 200);
      await working.drain<void>();
    },
  );

  test('close is idempotent and releases the public port', () async {
    final port = gateway.port;
    final closing = gateway.close();
    expect(identical(closing, gateway.close()), isTrue);
    await closing;
    final listener = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    await listener.close(force: true);
  });
}
