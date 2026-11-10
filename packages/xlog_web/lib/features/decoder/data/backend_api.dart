import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:http/http.dart' as http;
import 'package:web/web.dart' as web;

import '../../../browser/browser_upload_file.dart';
import '../domain/decoder_api.dart';
import '../domain/models.dart';

class BackendApi implements DecoderApi {
  BackendApi(
    this.baseUri, {
    http.Client? client,
    web.XMLHttpRequest Function()? createUploadRequest,
  }) : _client = client ?? http.Client(),
       _createUploadRequest =
           createUploadRequest ?? (() => web.XMLHttpRequest());

  final Uri baseUri;
  final http.Client _client;
  final web.XMLHttpRequest Function() _createUploadRequest;
  final _uploads = <web.XMLHttpRequest>{};

  static const _headers = {'Accept': 'application/json'};

  Uri endpoint(String path, [Map<String, String>? query]) =>
      baseUri.resolve(path).replace(queryParameters: query);

  Future<Map<String, dynamic>> _json(String method, Uri uri) async {
    try {
      final request = http.Request(method, uri)..headers.addAll(_headers);
      final streamed = await _client
          .send(request)
          .timeout(const Duration(seconds: 20));
      final response = await http.Response.fromStream(
        streamed,
      ).timeout(const Duration(seconds: 20));
      return _decode(response.statusCode, response.body);
    } on ApiException {
      rethrow;
    } catch (_) {
      throw const ApiException('network');
    }
  }

  @override
  Future<int> health() async {
    final json = await _json('GET', endpoint('api/health'));
    return (json['maxUploadBytes'] as num?)?.toInt() ?? 256 * 1024 * 1024;
  }

  @override
  Future<RemoteJob> job(String id) async => RemoteJob.fromJson(
    await _json('GET', endpoint('api/jobs/${Uri.encodeComponent(id)}')),
  );

  @override
  Future<void> cancel(String id) async {
    await _json('DELETE', endpoint('api/jobs/${Uri.encodeComponent(id)}'));
  }

  @override
  Future<RemoteJob> upload(
    UploadFile source, {
    required void Function(double progress) onProgress,
  }) {
    if (source is! BrowserUploadFile) {
      return Future.error(ArgumentError('Expected a native browser upload'));
    }
    final file = source.file;
    final result = Completer<RemoteJob>();
    final request = _createUploadRequest();
    _uploads.add(request);
    request.open(
      'POST',
      endpoint('api/jobs', {'filename': file.name}).toString(),
    );
    request.timeout = 15 * 60 * 1000;
    for (final header in _headers.entries) {
      request.setRequestHeader(header.key, header.value);
    }
    request.setRequestHeader('Content-Type', 'application/octet-stream');
    request.upload.onprogress = ((web.ProgressEvent event) {
      if (event.lengthComputable && event.total > 0) {
        onProgress(event.loaded / event.total);
      }
    }).toJS;
    void fail(String code) {
      if (!result.isCompleted) result.completeError(ApiException(code));
    }

    request.onload = ((web.Event _) {
      try {
        final data = _decode(request.status, request.responseText);
        if (!result.isCompleted) result.complete(RemoteJob.fromJson(data));
      } on ApiException catch (error) {
        if (!result.isCompleted) result.completeError(error);
      } catch (_) {
        fail('unknown');
      }
    }).toJS;
    request.onerror = ((web.Event _) => fail('network')).toJS;
    request.ontimeout = ((web.Event _) => fail('network')).toJS;
    request.onabort = ((web.Event _) => fail('cancelled')).toJS;
    // Send the native File directly. Never materialize the full upload in Dart.
    try {
      request.send(file);
    } catch (_) {
      fail('network');
    }
    return result.future.whenComplete(() => _uploads.remove(request));
  }

  /// Keep browser-native downloads so results are not buffered into JS memory.
  @override
  String? downloadLink(RemoteJob job) {
    if (job.downloadUrl == null) return null;
    final uri = baseUri.resolve(job.downloadUrl!);
    if (!const {'http', 'https'}.contains(uri.scheme) ||
        uri.origin != baseUri.origin ||
        !uri.path.startsWith('/api/jobs/')) {
      return null;
    }
    return uri.toString();
  }

  @override
  void close() {
    for (final request in _uploads.toList()) {
      request.abort();
    }
    _client.close();
  }
}

Map<String, dynamic> _decode(int status, String body) {
  Map<String, dynamic>? data;
  try {
    data = (jsonDecode(body) as Map).cast<String, dynamic>();
  } catch (_) {
    throw ApiException('unknown', statusCode: status);
  }
  if (status < 200 || status >= 300) {
    final error = data['error'];
    throw ApiException(
      _normalizeCode(
        error is Map ? error['code'] as String? ?? 'unknown' : 'unknown',
      ),
      statusCode: status,
    );
  }
  return data;
}

String _normalizeCode(String code) => switch (code) {
  'job_not_found' || 'result_expired' => 'not_found',
  'job_busy' => 'not_cancellable',
  'empty_upload' || 'invalid_filename' => 'invalid_input',
  'origin_denied' => 'forbidden',
  'upload_timeout' => 'network',
  _ => code,
};
