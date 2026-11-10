import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:test/test.dart';
import 'package:xlog_server/src/infrastructure/execution/isolate_job_executor.dart';
import 'package:xlog_server/src/infrastructure/storage/file_job_storage.dart';
import 'package:xlog_server/xlog_server.dart';

void main() {
  test(
    'concurrent HTTP uploads, bounded workers and downloads remain independent',
    () async {
      final fixtures =
          jsonDecode(
                File(
                  '../xlog_decode/test/fixtures/mars_reference.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      List<int> unhex(String value) => [
        for (var offset = 0; offset < value.length; offset += 2)
          int.parse(value.substring(offset, offset + 2), radix: 16),
      ];
      final frame = unhex(fixtures['modern']['07'] as String);
      final plain = unhex(fixtures['plain'] as String);
      final root = await Directory.systemTemp.createTemp('xlog-concurrency-');
      final storage = _ObservedStorage(
        FileJobStorage(root),
        expectedUploads: 3,
      );
      final executor = _GatedExecutor();
      final app = await XlogServer.create(
        ServerConfig(
          dataDirectory: root,
          keys: {
            'fixture': ServerKey('Fixture', fixtures['privateKey'] as String),
          },
          maxConcurrentJobs: 2,
          maxQueuedJobs: 1,
          maxUploadBytes: frame.length * 4,
          maxOutputBytes: plain.length * 4,
        ),
        storage: storage,
        executor: executor,
      );
      final listener = await shelf_io.serve(app.handler, '127.0.0.1', 0);
      final client = HttpClient()..maxConnectionsPerHost = 32;
      addTearDown(() async {
        if (!executor.release.isCompleted) executor.release.complete();
        client.close(force: true);
        await listener.close(force: true);
        await app.close();
        await root.delete(recursive: true);
      });
      Uri uri(String path) =>
          Uri.parse('http://127.0.0.1:${listener.port}$path');
      Map<String, dynamic> object(List<int> bytes) =>
          jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      Future<(int, List<int>)> request(
        String method,
        String path, {
        List<int>? body,
      }) async {
        final call = await client.openUrl(method, uri(path));
        if (body != null) call.add(body);
        final response = await call.close();
        return (
          response.statusCode,
          await response.fold<List<int>>(
            [],
            (all, chunk) => all..addAll(chunk),
          ),
        );
      }

      Future<void> verifyBusyServer() async {
        final health = await Future.wait([
          for (var i = 0; i < 12; i++) request('GET', '/api/health'),
        ]).timeout(const Duration(seconds: 5));
        expect(health.map((response) => response.$1), everyElement(200));
        final rejected = await Future.wait([
          for (var i = 0; i < 6; i++)
            request('POST', '/api/jobs?filename=overflow.xlog', body: frame),
        ]);
        expect(rejected.map((response) => response.$1), everyElement(429));
        for (final response in rejected) {
          expect(object(response.$2)['error']['code'], 'queue_full');
        }
        expect(await root.list().length, 3);
      }

      // The storage observation acknowledges bytes received by the server,
      // rather than assuming client.flush means admission has happened.
      final uploads = await Future.wait([
        for (var i = 0; i < 3; i++)
          () async {
            final call = await client.postUrl(
              uri('/api/jobs?filename=client-$i.xlog'),
            );
            call.bufferOutput = false;
            call.add(frame);
            await call.flush();
            return call;
          }(),
      ]);
      await storage.firstChunksReceived.future.timeout(
        const Duration(seconds: 5),
      );
      expect(storage.activeUploads, 3);
      expect(executor.started, 0);
      await verifyBusyServer();

      final admitted = await Future.wait([
        for (var i = 0; i < uploads.length; i++)
          () async {
            for (var copy = 0; copy < i; copy++) {
              uploads[i].add(frame);
            }
            final response = await uploads[i].close();
            expect(response.statusCode, 202);
            return object(
              await response.fold<List<int>>(
                [],
                (all, chunk) => all..addAll(chunk),
              ),
            );
          }(),
      ]);
      await executor.twoWorkersStarted.future.timeout(
        const Duration(seconds: 5),
      );
      expect(executor.started, 2);
      expect(executor.active, 2);
      expect(storage.activeUploads, 0);
      expect(admitted.map((job) => job['id']).toSet(), hasLength(3));
      final statuses = await Future.wait([
        for (final job in admitted) request('GET', '/api/jobs/${job['id']}'),
      ]);
      expect(
        statuses.map((response) => object(response.$2)['status']),
        unorderedEquals(['running', 'running', 'queued']),
      );
      await verifyBusyServer();

      executor.release.complete();
      final healthDuringDecode = Future.wait([
        for (var i = 0; i < 12; i++) request('GET', '/api/health'),
      ]).timeout(const Duration(seconds: 5));
      Future<Map<String, dynamic>> finished(String id) async {
        while (true) {
          final response = await request('GET', '/api/jobs/$id');
          expect(response.$1, 200);
          final job = object(response.$2);
          if (['success', 'warning', 'failure'].contains(job['status'])) {
            return job;
          }
        }
      }

      final completed = await Future.wait([
        for (final job in admitted) finished(job['id'] as String),
      ]).timeout(const Duration(seconds: 10));
      expect(
        (await healthDuringDecode).map((response) => response.$1),
        everyElement(200),
      );
      expect(executor.maxActive, 2);
      expect(executor.started, 3);
      expect(completed.map((job) => job['downloadUrl']).toSet(), hasLength(3));
      for (var i = 0; i < completed.length; i++) {
        expect(completed[i]['status'], anyOf('success', 'warning'));
        expect(completed[i]['name'], 'client-$i.xlog');
        expect(completed[i]['blockCount'], i + 1);
        expect(completed[i]['outputBytes'], plain.length * (i + 1));
      }
      final downloads = await Future.wait([
        for (var copy = 0; copy < 2; copy++)
          for (final job in completed)
            request('GET', job['downloadUrl'] as String),
        request('GET', '/api/health'),
      ]).timeout(const Duration(seconds: 5));
      for (var index = 0; index < 6; index++) {
        expect(downloads[index].$1, 200);
        expect(downloads[index].$2, [
          for (var copy = 0; copy <= index % 3; copy++) ...plain,
        ]);
      }
      expect(downloads.last.$1, 200);

      for (final job in completed) {
        expect(job['downloadUrl'], '/api/jobs/${job['id']}/download');
      }
      expect(
        (await request('DELETE', '/api/jobs/${completed.first['id']}')).$1,
        200,
      );
      expect(
        (await request('GET', completed[1]['downloadUrl'] as String)).$1,
        200,
      );
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );
}

/// Observes production file storage without changing its writes or limits.
class _ObservedStorage implements JobStorage {
  _ObservedStorage(this.delegate, {required this.expectedUploads});

  final JobStorage delegate;
  final int expectedUploads;
  final firstChunksReceived = Completer<void>();
  int activeUploads = 0;
  int _received = 0;

  @override
  Future<void> initialize() => delegate.initialize();
  @override
  Future<String> createWorkspace(String id) => delegate.createWorkspace(id);
  @override
  Future<void> deleteInput(String id) => delegate.deleteInput(id);
  @override
  Future<void> deleteWorkspace(String id) => delegate.deleteWorkspace(id);
  @override
  Future<StoredResult> readResult(String id, String filename) =>
      delegate.readResult(id, filename);

  @override
  Future<void> writeUpload(
    String id,
    Stream<List<int>> source, {
    required int maxBytes,
    required Duration timeout,
  }) async {
    activeUploads++;
    Stream<List<int>> observed() async* {
      var first = true;
      await for (final chunk in source) {
        if (first) {
          first = false;
          if (++_received == expectedUploads) firstChunksReceived.complete();
        }
        yield chunk;
      }
    }

    try {
      await delegate.writeUpload(
        id,
        observed(),
        maxBytes: maxBytes,
        timeout: timeout,
      );
    } finally {
      activeUploads--;
    }
  }
}

/// Holds only scheduling for inspection; every admitted job uses a real isolate.
class _GatedExecutor implements JobExecutor {
  final release = Completer<void>();
  final twoWorkersStarted = Completer<void>();
  int started = 0;
  int active = 0;
  int maxActive = 0;

  @override
  Future<DecodeResult> execute(DecodeTask task) async {
    started++;
    active++;
    if (active > maxActive) maxActive = active;
    if (started == 2) twoWorkersStarted.complete();
    try {
      await release.future;
      return await const IsolateJobExecutor().execute(task);
    } finally {
      active--;
    }
  }
}
