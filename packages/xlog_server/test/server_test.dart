import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:test/test.dart';
import 'package:xlog_server/xlog_server.dart';

final fixtures =
    jsonDecode(
          File(
            '../xlog_decode/test/fixtures/mars_reference.json',
          ).readAsStringSync(),
        )
        as Map<String, dynamic>;
List<int> unhex(String value) => [
  for (var i = 0; i < value.length; i += 2)
    int.parse(value.substring(i, i + 2), radix: 16),
];
List<int> frame(String magic) => unhex(fixtures['modern'][magic] as String);

void main() {
  late Directory temporary;
  late XlogServer server;
  late HttpClient client;
  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('xlog-api-test-');
    client = HttpClient();
    server = await XlogServer.bind(
      ServerConfig(
        dataDirectory: temporary,
        keys: {
          'mars': ServerKey('Mars test', fixtures['privateKey'] as String),
        },
      ),
      port: 0,
    );
  });
  tearDown(() async {
    client.close(force: true);
    await server.close();
    if (await temporary.exists()) await temporary.delete(recursive: true);
  });
  Future<(int, List<int>)> request(
    String method,
    String path, {
    List<int>? body,
    String? origin,
  }) async {
    final call = await client.openUrl(
      method,
      Uri.parse('http://127.0.0.1:${server.port}$path'),
    );
    if (origin != null) call.headers.set('Origin', origin);
    if (body != null) {
      call.headers.contentType = ContentType.binary;
      call.add(body);
    }
    final response = await call.close();
    return (
      response.statusCode,
      await response.fold<List<int>>([], (all, bytes) => all..addAll(bytes)),
    );
  }

  Map<String, dynamic> object(List<int> bytes) =>
      jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
  Future<Map<String, dynamic>> waitJob(String id) async {
    for (var i = 0; i < 200; i++) {
      final response = await request('GET', '/api/jobs/$id');
      final job = object(response.$2);
      if (['success', 'warning', 'failure'].contains(job['status'])) return job;
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    throw StateError('Job timeout');
  }

  test('health is open and key metadata is not exposed', () async {
    expect((await request('GET', '/api/health')).$1, 200);
    final response = await request('GET', '/api/keys');
    expect(response.$1, 404);
    expect(object(response.$2)['error']['code'], 'not_found');
    expect(utf8.decode(response.$2), isNot(contains(fixtures['privateKey'])));
    expect(utf8.decode(response.$2), isNot(contains('Mars test')));
    expect(
      (await request('GET', '/api/health', origin: 'https://bad.example')).$1,
      200,
    );
    final health = await request(
      'GET',
      '/api/health',
      origin: 'http://localhost:18780',
    );
    expect(health.$1, 200);
    expect(object(health.$2)['supportsZip'], true);
    expect(
      (await request(
        'GET',
        '/api/health',
        origin: 'http://127.0.0.1:${server.port}',
      )).$1,
      200,
    );
  });
  test(
    'open upload decodes encrypted content and downloads by job id',
    () async {
      final uploaded = await request(
        'POST',
        '/api/jobs?filename=encrypted.xlog',
        body: frame('07'),
      );
      expect(uploaded.$1, 202);
      final job = await waitJob(object(uploaded.$2)['id'] as String);
      expect(job['status'], 'success');
      expect(job['outputBytes'], unhex(fixtures['plain'] as String).length);
      expect(jsonEncode(job), isNot(contains(fixtures['privateKey'])));
      expect(jsonEncode(job), isNot(contains(temporary.path)));
      expect(job['downloadUrl'], '/api/jobs/${job['id']}/download');
      final downloaded = await request('GET', job['downloadUrl'] as String);
      expect(downloaded.$1, 200);
      expect(downloaded.$2, unhex(fixtures['plain'] as String));
      expect((await request('DELETE', '/api/jobs/${job['id']}')).$1, 200);
      expect((await request('GET', job['downloadUrl'] as String)).$1, 404);
    },
  );
  test(
    'ZIP entries use disk, flatten paths and produce a download archive',
    () async {
      final input = Archive()
        ..add(ArchiveFile.bytes('../outside.xlog', frame('09')))
        ..add(ArchiveFile.bytes('nested/app.xlog', frame('0d')))
        ..add(ArchiveFile.string('ignored.txt', 'not a log'));
      final uploaded = await request(
        'POST',
        '/api/jobs?filename=logs.zip',
        body: ZipEncoder().encodeBytes(input),
      );
      expect(uploaded.$1, 202);
      final job = await waitJob(object(uploaded.$2)['id'] as String);
      expect(job['status'], 'success');
      final downloaded = await request('GET', job['downloadUrl'] as String);
      final archive = ZipDecoder().decodeBytes(downloaded.$2);
      expect(archive.files.map((f) => f.name), ['1_outside.log', '2_app.log']);
      for (final entry in archive) {
        expect(entry.content, unhex(fixtures['plain'] as String));
      }
      expect(await File('${temporary.path}/outside.xlog').exists(), false);
    },
  );
  test(
    'bad logs fail without exposing paths and unsupported types are rejected',
    () async {
      expect(
        (await request('POST', '/api/jobs?filename=a.txt', body: [1])).$1,
        415,
      );
      final uploaded = await request(
        'POST',
        '/api/jobs?filename=bad.xlog',
        body: [255],
      );
      final job = await waitJob(object(uploaded.$2)['id'] as String);
      expect(job['status'], 'failure');
      expect(job['error']['code'], 'decode_failed');
      expect(jsonEncode(job), isNot(contains(temporary.path)));
      expect(job.containsKey('downloadUrl'), false);
    },
  );
  test('upload limit rejects content and cleans temporary files', () async {
    await server.close();
    server = await XlogServer.bind(
      ServerConfig(dataDirectory: temporary, maxUploadBytes: 16),
      port: 0,
    );
    final call = await client.postUrl(
      Uri.parse('http://127.0.0.1:${server.port}/api/jobs?filename=big.xlog'),
    );
    call.contentLength = 32;
    call.add(List.filled(32, 1));
    final response = await call.close();
    expect(response.statusCode, 413);
    await response.drain<void>();
    expect(await temporary.list().length, 0);
  });
  test('an upload in progress consumes admission capacity', () async {
    await server.close();
    server = await XlogServer.bind(
      ServerConfig(
        dataDirectory: temporary,
        maxConcurrentJobs: 1,
        maxQueuedJobs: 0,
      ),
      port: 0,
    );
    final upload = await client.postUrl(
      Uri.parse('http://127.0.0.1:${server.port}/api/jobs?filename=held.xlog'),
    );
    upload.add([255]);
    await upload.flush();
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(
      (await request(
        'POST',
        '/api/jobs?filename=next.xlog',
        body: frame('09'),
      )).$1,
      429,
    );
    final accepted = await upload.close();
    expect(accepted.statusCode, 202);
    await accepted.drain<void>();
  });
  test('expired task metadata and results are removed on access', () async {
    await server.close();
    server = await XlogServer.bind(
      ServerConfig(
        dataDirectory: temporary,
        jobTtl: const Duration(milliseconds: 40),
      ),
      port: 0,
    );
    final uploaded = await request(
      'POST',
      '/api/jobs?filename=short.xlog',
      body: frame('09'),
    );
    final id = object(uploaded.$2)['id'] as String;
    final job = await waitJob(id);
    expect(job['status'], 'success');
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect((await request('GET', '/api/jobs/$id')).$1, 404);
    expect(await Directory('${temporary.path}/$id').exists(), false);
  });
  test('decoded output budget failure publishes no result', () async {
    await server.close();
    server = await XlogServer.bind(
      ServerConfig(dataDirectory: temporary, maxOutputBytes: 32),
      port: 0,
    );
    final uploaded = await request(
      'POST',
      '/api/jobs?filename=large.xlog',
      body: frame('09'),
    );
    final id = object(uploaded.$2)['id'] as String;
    final job = await waitJob(id);
    expect(job['status'], 'failure');
    expect(job.containsKey('downloadUrl'), false);
    expect(await Directory('${temporary.path}/$id').exists(), false);
  });
  test('ZIP entry and metadata limits reject oversized archives', () async {
    final archive = Archive();
    for (var i = 0; i < 129; i++) {
      archive.add(ArchiveFile.bytes('$i.xlog', frame('09')));
    }
    final uploaded = await request(
      'POST',
      '/api/jobs?filename=many.zip',
      body: ZipEncoder().encodeBytes(archive),
    );
    final job = await waitJob(object(uploaded.$2)['id'] as String);
    expect(job['status'], 'failure');
  });
  test(
    'built frontend assets are served same-origin without exposing symlink targets',
    () async {
      await server.close();
      final root = await Directory('${temporary.path}/web').create();
      await File('${root.path}/index.html').writeAsString('<h1>Xlog Web</h1>');
      await File('${temporary.path}/secret').writeAsString('private material');
      await Link('${root.path}/secret.txt').create('${temporary.path}/secret');
      server = await XlogServer.bind(
        ServerConfig(
          dataDirectory: Directory('${temporary.path}/data'),
          webRoot: root,
        ),
        port: 0,
      );
      final page = await request('GET', '/');
      expect(page.$1, 200);
      expect(utf8.decode(page.$2), '<h1>Xlog Web</h1>');
      expect((await request('GET', '/secret.txt')).$1, 404);
    },
  );
  test('public binding serves the open API without credentials', () async {
    await server.close();
    server = await XlogServer.bind(
      ServerConfig(dataDirectory: temporary),
      host: '0.0.0.0',
      port: 0,
    );
    expect(server.address, InternetAddress.anyIPv4);
    expect((await request('GET', '/api/health')).$1, 200);
    final uploaded = await request(
      'POST',
      '/api/jobs?filename=public.xlog',
      body: frame('09'),
    );
    expect(uploaded.$1, 202);
    final job = await waitJob(object(uploaded.$2)['id'] as String);
    expect(job['status'], 'success');
    final downloaded = await request('GET', '/api/jobs/${job['id']}/download');
    expect(downloaded.$1, 200);
    expect(downloaded.$2, unhex(fixtures['plain'] as String));
  });
}
