import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// dart:io HttpClient waits for its request sink before exposing a response.
/// Uploads instead use a single-request connection with concurrent directions,
/// so a backend rejection never waits for the browser to finish its body.
class ApiUploadTunnel {
  Socket? _browser;
  Socket? _upstream;
  bool _closed = false;

  Future<void> forward(HttpRequest request, Uri target) async {
    var responseStarted = false;
    Future<void>? uploadFinished;
    try {
      final upstream = await Socket.connect(target.host, target.port);
      _upstream = upstream;
      if (_closed) return;
      final browser = await request.response.detachSocket(writeHeaders: false);
      _browser = browser;
      if (_closed) return;
      upstream.add(latin1.encode(_requestHeaders(request, target)));
      await upstream.flush();
      final uploadInput = StreamIterator<List<int>>(browser);
      final upload = _upload(uploadInput, upstream);
      // A browser failure must also stop waiting for an upstream response.
      uploadFinished = upload.then<void>(
        (_) {},
        onError: (Object _) {
          upstream.destroy();
        },
      );
      await for (final chunk in _response(
        upstream,
        onFinalResponse: () {
          // Stop consuming upload bytes as soon as final response headers arrive,
          // while leaving the browser's write side open for the response body.
          unawaited(uploadInput.cancel());
        },
      )) {
        responseStarted = true;
        browser.add(chunk);
        await browser.flush();
      }
    } catch (_) {
      if (_browser == null) rethrow;
      if (!responseStarted) {
        try {
          _browser!.add(
            latin1.encode(
              'HTTP/1.1 502 Bad Gateway\r\nConnection: close\r\nContent-Length: 0\r\n\r\n',
            ),
          );
          await _browser!.flush();
        } catch (_) {
          // The browser may have disconnected first.
        }
      }
    } finally {
      // Finish the response before interrupting any remaining upload. Destroy
      // wakes a paused socket read/write, so no upload future stays suspended.
      close();
      await uploadFinished;
    }
  }

  Future<void> _upload(StreamIterator<List<int>> input, Socket upstream) async {
    while (await input.moveNext()) {
      upstream.add(input.current);
      await upstream.flush();
    }
    // Forward a browser FIN too; otherwise an interrupted request would leave
    // the backend waiting forever for the rest of its declared body.
    await upstream.close();
  }

  void close() {
    _closed = true;
    _browser?.destroy();
    _upstream?.destroy();
  }
}

String _requestHeaders(HttpRequest request, Uri target) {
  final path =
      '${target.path.isEmpty ? '/' : target.path}${target.hasQuery ? '?${target.query}' : ''}';
  final output = StringBuffer('${request.method} $path HTTP/1.1\r\n');
  final excluded = _hopFields(request.headers.value('connection'))
    ..add('content-length');
  request.headers.forEach((name, values) {
    if (!excluded.contains(name.toLowerCase())) {
      for (final value in values) {
        output.write('$name: $value\r\n');
      }
    }
  });
  // The detached socket still contains original chunk framing, if present.
  if (request.headers.chunkedTransferEncoding) {
    output.write('transfer-encoding: chunked\r\n');
  } else if (request.contentLength >= 0) {
    output.write('content-length: ${request.contentLength}\r\n');
  }
  output.write('connection: close\r\n\r\n');
  return output.toString();
}

Stream<List<int>> _response(
  Socket socket, {
  required void Function() onFinalResponse,
}) async* {
  var headers = <int>[];
  var body = false;
  await for (final chunk in socket) {
    if (body) {
      yield chunk;
      continue;
    }
    headers.addAll(chunk);
    while (true) {
      final end = _headerEnd(headers);
      if (end < 0) {
        if (headers.length > 64 * 1024) {
          throw const HttpException('Upstream headers too large');
        }
        break;
      }
      if (end + 4 > 64 * 1024) {
        throw const HttpException('Upstream headers too large');
      }
      final lines = latin1.decode(headers.sublist(0, end)).split('\r\n');
      final status = RegExp(
        r'^HTTP/1\.[01] (\d{3})(?: .*)?$',
      ).firstMatch(lines.first);
      if (status == null) throw const HttpException('Invalid upstream status');
      final code = int.parse(status.group(1)!);
      if (code == 101 || code < 100) {
        throw const HttpException('Unsupported upstream status');
      }
      body = code >= 200;
      if (body) onFinalResponse();
      yield latin1.encode(_responseHeaders(lines, finalResponse: body));
      headers = headers.sublist(end + 4);
      if (body) {
        if (headers.isNotEmpty) yield headers;
        headers = [];
        break;
      }
    }
  }
  if (!body) throw const HttpException('Incomplete upstream response');
}

int _headerEnd(List<int> bytes) {
  for (var i = 0; i + 3 < bytes.length; i++) {
    if (bytes[i] == 13 &&
        bytes[i + 1] == 10 &&
        bytes[i + 2] == 13 &&
        bytes[i + 3] == 10) {
      return i;
    }
  }
  return -1;
}

String _responseHeaders(List<String> lines, {required bool finalResponse}) {
  final fields = <(String, String)>[];
  for (final line in lines.skip(1)) {
    final colon = line.indexOf(':');
    if (colon < 1) throw const HttpException('Invalid upstream header');
    fields.add((
      line.substring(0, colon).toLowerCase(),
      line.substring(colon + 1).trim(),
    ));
  }
  final connection = fields
      .where((field) => field.$1 == 'connection')
      .map((field) => field.$2)
      .join(',');
  final excluded = _hopFields(connection)
    ..remove('transfer-encoding')
    ..remove('content-length');
  if (fields.any((field) => field.$1 == 'transfer-encoding')) {
    // Transfer coding frames the raw response body; never send a competing
    // Content-Length, even if an upstream incorrectly supplied both.
    excluded.add('content-length');
  }
  return '${lines.first}\r\n${fields.where((field) => !excluded.contains(field.$1)).map((field) => '${field.$1}: ${field.$2}\r\n').join()}${finalResponse ? 'connection: close\r\n' : ''}\r\n';
}

Set<String> _hopFields(String? connection) => {
  'connection',
  'keep-alive',
  'proxy-authenticate',
  'proxy-authorization',
  'te',
  'trailer',
  'transfer-encoding',
  'upgrade',
  ...?connection?.split(',').map((value) => value.trim().toLowerCase()),
};
