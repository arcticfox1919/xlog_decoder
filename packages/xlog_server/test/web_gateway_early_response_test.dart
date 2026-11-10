import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../../../scripts/src/dev_gateway.dart';

void main() {
  late ServerSocket upstream;
  late HttpServer frontend;
  late DevGateway gateway;
  late HttpClient client;
  late Set<Socket> connections;
  late void Function(Socket, String) onHeaders;

  setUp(() async {
    connections = {};
    upstream = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    frontend = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    frontend.listen((request) => request.response.close());
    onHeaders = (socket, _) =>
        unawaited(_reply(socket, 200, '{"status":"ok"}'));
    upstream.listen((socket) {
      connections.add(socket);
      var headers = '';
      var delivered = false;
      socket.listen(
        (chunk) {
          if (delivered) return;
          headers += latin1.decode(chunk);
          if (headers.contains('\r\n\r\n')) {
            delivered = true;
            onHeaders(
              socket,
              headers.substring(0, headers.indexOf('\r\n\r\n')),
            );
          }
        },
        onError: (Object _) {},
        onDone: () => connections.remove(socket),
      );
    });
    gateway = await DevGateway.bind(
      port: 0,
      backend: Uri.parse('http://127.0.0.1:${upstream.port}'),
      frontend: Uri.parse('http://127.0.0.1:${frontend.port}'),
    );
    client = HttpClient();
  });
  tearDown(() async {
    client.close(force: true);
    await gateway.close();
    for (final socket in connections.toList()) {
      socket.destroy();
    }
    await upstream.close();
    await frontend.close(force: true);
  });

  for (final code in [413, 429]) {
    for (final chunked in [false, true]) {
      test(
        'forwards early $code before ${chunked ? 'chunked' : 'fixed-length'} upload finishes',
        () async {
          final received = Completer<void>();
          final json =
              '{"error":{"code":"${code == 413 ? 'upload_too_large' : 'queue_full'}"}}';
          onHeaders = (socket, headers) {
            if (headers.startsWith('GET ')) {
              unawaited(_reply(socket, 200, '{"status":"ok"}'));
              return;
            }
            expect(headers, contains('filename=held.xlog&part=a%20b'));
            expect(
              headers.toLowerCase(),
              contains(
                chunked
                    ? 'transfer-encoding: chunked'
                    : 'content-length: 1048576',
              ),
            );
            received.complete();
            unawaited(_reply(socket, code, json, chunked: code == 429));
          };
          final browser = await Socket.connect(
            InternetAddress.loopbackIPv4,
            gateway.port,
          );
          addTearDown(browser.destroy);
          final response = browser.fold<List<int>>(
            [],
            (all, chunk) => all..addAll(chunk),
          );
          browser.write(
            'POST /api/jobs?filename=held.xlog&part=a%20b HTTP/1.1\r\n'
            'Host: localhost:${gateway.port}\r\n'
            '${chunked ? 'Transfer-Encoding: chunked' : 'Content-Length: 1048576'}\r\n\r\n',
          );
          if (chunked) browser.write('400\r\n');
          browser.add(List.filled(1024, 1));
          if (chunked) browser.write('\r\n');
          await browser.flush();
          await received.future.timeout(const Duration(seconds: 3));
          // The browser sends neither the remaining bytes nor a terminating
          // chunk. A complete response must still arrive and release the socket.
          final bytes = await response.timeout(const Duration(seconds: 3));
          final text = latin1.decode(bytes);
          expect(text, startsWith('HTTP/1.1 $code '));
          expect(text, contains(json));
          expect(text.toLowerCase(), contains('connection: close'));
          if (code == 429) {
            expect(text.toLowerCase(), contains('transfer-encoding: chunked'));
            expect(text.toLowerCase(), isNot(contains('content-length:')));
            expect(text, endsWith('\r\n0\r\n\r\n'));
          }
          final request = await client.getUrl(
            Uri.parse('http://127.0.0.1:${gateway.port}/api/health'),
          );
          final health = await request.close();
          expect(health.statusCode, 200);
          expect(await utf8.decoder.bind(health).join(), '{"status":"ok"}');
        },
      );
    }
  }

  for (final oversizedHeaders in [false, true]) {
    test(
      'upstream ${oversizedHeaders ? 'oversized headers' : 'exit'} releases an unfinished upload',
      () async {
        onHeaders = (socket, _) {
          if (oversizedHeaders) {
            unawaited(() async {
              socket.write(
                'HTTP/1.1 200 OK\r\nX-Oversized: ${'a' * (64 * 1024)}\r\n\r\n',
              );
              await socket.flush();
              await socket.close();
            }());
          } else {
            socket.destroy();
          }
        };
        final browser = await Socket.connect(
          InternetAddress.loopbackIPv4,
          gateway.port,
        );
        addTearDown(browser.destroy);
        final received = browser.fold<List<int>>(
          [],
          (all, chunk) => all..addAll(chunk),
        );
        browser.write(
          'POST /api/jobs?filename=held.xlog HTTP/1.1\r\n'
          'Host: localhost:${gateway.port}\r\nContent-Length: 1048576\r\n\r\n',
        );
        browser.add([1, 2, 3]);
        await browser.flush();
        final response = latin1.decode(
          await received.timeout(const Duration(seconds: 3)),
        );
        expect(response, startsWith('HTTP/1.1 502 '));
      },
    );
  }

  test(
    'gateway shutdown interrupts an unfinished upload and releases sockets',
    () async {
      final received = Completer<void>();
      onHeaders = (_, _) => received.complete();
      final browser = await Socket.connect(
        InternetAddress.loopbackIPv4,
        gateway.port,
      );
      addTearDown(browser.destroy);
      final closed = browser.drain<void>();
      browser.write(
        'POST /api/jobs?filename=held.xlog HTTP/1.1\r\n'
        'Host: localhost:${gateway.port}\r\nContent-Length: 1048576\r\n\r\n',
      );
      browser.add(List.filled(1024, 1));
      await browser.flush();
      await received.future.timeout(const Duration(seconds: 3));
      final port = gateway.port;
      await gateway.close().timeout(const Duration(seconds: 3));
      await closed.timeout(const Duration(seconds: 3));
      final reservation = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        port,
      );
      await reservation.close();
    },
  );
}

Future<void> _reply(
  Socket socket,
  int code,
  String body, {
  bool chunked = false,
}) async {
  final bytes = utf8.encode(body);
  socket.write(
    'HTTP/1.1 $code Result\r\nContent-Type: application/json\r\n'
    '${chunked ? 'Transfer-Encoding: chunked\r\nContent-Length: 999999' : 'Content-Length: ${bytes.length}'}\r\n'
    'Connection: close\r\n\r\n',
  );
  if (chunked) socket.write('${bytes.length.toRadixString(16)}\r\n');
  socket.add(bytes);
  if (chunked) socket.write('\r\n0\r\n\r\n');
  await socket.flush();
  await socket.close();
}
