import 'dart:async';
import 'dart:io';

import 'api_upload_tunnel.dart';
import 'bootstrap_urls.dart';
import 'web_socket_relay.dart';

/// A same-origin development entry point. Bodies remain streams in both
/// directions; only WebSocket protocol messages are framed by dart:io.
class DevGateway {
  DevGateway._(this._server, this.backend, this.frontend, this.devtools) {
    _server.listen((request) => unawaited(_forward(request)));
  }

  final HttpServer _server;
  final Uri backend;
  final Uri frontend;
  final Uri? devtools;
  final _client = HttpClient()..autoUncompress = false;
  final _sockets = <WebSocket>{};
  final _relays = <WebSocketRelay>{};
  final _uploads = <ApiUploadTunnel>{};
  Future<void>? _closing;

  int get port => _server.port;

  static Future<DevGateway> bind({
    required int port,
    required Uri backend,
    required Uri frontend,
    Uri? devtools,
  }) async => DevGateway._(
    await HttpServer.bind(InternetAddress.loopbackIPv4, port),
    backend,
    frontend,
    devtools,
  );

  Future<void> _forward(HttpRequest request) async {
    HttpClientRequest? outgoing;
    try {
      if (_closing != null) throw const HttpException('Gateway is closing');
      final api =
          request.uri.path == '/api' || request.uri.path.startsWith('/api/');
      final base = api ? backend : frontend;
      final target = base.replace(
        pathSegments: request.uri.pathSegments,
        query: request.uri.hasQuery ? request.uri.query : null,
      );
      if (WebSocketTransformer.isUpgradeRequest(request)) {
        await _webSocket(request, target);
        return;
      }
      if (api && request.contentLength != 0) {
        final upload = ApiUploadTunnel();
        _uploads.add(upload);
        try {
          await upload.forward(request, target);
        } finally {
          _uploads.remove(upload);
          upload.close();
        }
        return;
      }
      outgoing = await _client.openUrl(request.method, target);
      outgoing.followRedirects = false;
      outgoing.bufferOutput = false;
      _copyHeaders(request.headers, outgoing.headers);
      final bootstrap = !api && request.uri.path.endsWith('.dart.bootstrap.js');
      if (bootstrap) outgoing.headers.set('accept-encoding', 'identity');
      // Keep the public Host and Origin together so the backend sees a
      // same-origin request and Jaspr generates public development URLs.
      await outgoing.addStream(request);
      final incoming = await outgoing.close();
      request.response
        ..statusCode = incoming.statusCode
        ..reasonPhrase = incoming.reasonPhrase
        ..bufferOutput = false;
      _copyHeaders(incoming.headers, request.response.headers);
      if (bootstrap && incoming.statusCode == HttpStatus.ok) {
        request.response.headers
          ..contentLength = -1
          ..removeAll(HttpHeaders.etagHeader)
          ..set(HttpHeaders.cacheControlHeader, 'no-store');
        final publicOrigin = request.requestedUri.origin;
        final redirects = <String, String>{
          for (final upstream in [frontend, ?devtools])
            for (final host in ['localhost', '127.0.0.1']) ...{
              'http://$host:${upstream.port}/': '$publicOrigin/',
              'ws://$host:${upstream.port}/':
                  '${publicOrigin.replaceFirst('http', 'ws')}/',
            },
        };
        await request.response.addStream(
          redirectBootstrapUrls(incoming, redirects),
        );
      } else {
        await request.response.addStream(incoming);
      }
      await request.response.close();
    } catch (_) {
      outgoing?.abort();
      // Upstream errors after streaming began can only close the response.
      try {
        request.response.statusCode = HttpStatus.badGateway;
        request.response.write('Development service unavailable.');
      } catch (_) {
        // The connection may already be closed or have committed its headers.
      }
      try {
        await request.response.close();
      } catch (_) {
        // A disconnected browser must not produce an unhandled server error.
      }
    }
  }

  Future<void> _webSocket(HttpRequest request, Uri target) async {
    final headers = <String, dynamic>{};
    final excluded = _hopHeaders(request.headers)
      ..addAll({
        'sec-websocket-key',
        'sec-websocket-version',
        'sec-websocket-protocol',
        'sec-websocket-extensions',
      });
    request.headers.forEach((name, values) {
      if (!excluded.contains(name.toLowerCase())) headers[name] = values;
    });
    final protocols = request.headers
        .value('sec-websocket-protocol')
        ?.split(',')
        .map((value) => value.trim())
        .toList();
    final upstream = await WebSocket.connect(
      target
          .replace(scheme: target.scheme == 'https' ? 'wss' : 'ws')
          .toString(),
      headers: headers,
      protocols: protocols,
      customClient: _client,
    );
    _sockets.add(upstream);
    WebSocketRelay? relay;
    try {
      if (_closing != null) return;
      final downstream = await WebSocketTransformer.upgrade(
        request,
        protocolSelector: (_) => upstream.protocol,
      );
      _sockets.remove(upstream);
      relay = WebSocketRelay(upstream, downstream);
      _relays.add(relay);
      await relay.done;
    } finally {
      _sockets.remove(upstream);
      _relays.remove(relay);
      if (relay != null) {
        await relay.close();
      } else {
        await upstream.close();
      }
    }
  }

  Future<void> close() => _closing ??= _close();

  Future<void> _close() async {
    _client.close(force: true);
    for (final upload in _uploads.toList()) {
      upload.close();
    }
    await Future.wait([
      _server.close(force: true),
      for (final socket in _sockets.toList()) socket.close(),
      for (final relay in _relays.toList()) relay.close(),
    ]);
  }
}

Set<String> _hopHeaders(HttpHeaders headers) => {
  'connection',
  'keep-alive',
  'proxy-authenticate',
  'proxy-authorization',
  'te',
  'trailer',
  'transfer-encoding',
  'upgrade',
  ...?headers
      .value('connection')
      ?.split(',')
      .map((value) => value.trim().toLowerCase()),
};

void _copyHeaders(HttpHeaders source, HttpHeaders destination) {
  final excluded = _hopHeaders(source);
  source.forEach((name, values) {
    if (!excluded.contains(name.toLowerCase())) destination.set(name, values);
  });
}
