import 'dart:async';

import 'package:test/test.dart';
import 'package:xlog_server/src/application/job_limits.dart';
import 'package:xlog_server/src/application/job_service.dart';
import 'package:xlog_server/src/application/ports/job_executor.dart';
import 'package:xlog_server/src/application/ports/job_storage.dart';
import 'package:xlog_server/src/domain/decode_result.dart';
import 'package:xlog_server/src/domain/decode_task.dart';
import 'package:xlog_server/src/domain/job_snapshot.dart';
import 'package:xlog_server/src/domain/job_status.dart';
import 'package:xlog_server/src/domain/server_key.dart';
import 'package:xlog_server/src/domain/service_exception.dart';
import 'package:xlog_server/src/domain/stored_result.dart';

void main() {
  late FakeStorage storage;
  late ControlledExecutor executor;
  late JobService service;
  late DateTime now;
  late List<Object> cleanupErrors;
  var nextId = 0;

  JobService create({
    JobLimits? limits,
    Map<String, ServerKey> keys = const {},
  }) => JobService(
    storage: storage,
    executor: executor,
    limits: limits ?? JobLimits(maxConcurrentJobs: 1, maxQueuedJobs: 1),
    keys: keys,
    clock: () => now,
    idFactory: () => 'id-${nextId++}',
    onCleanupError: (error, _) => cleanupErrors.add(error),
  );

  Future<JobSnapshot> submit([String name = 'app.xlog']) =>
      service.submit(name, Stream.value([1]));

  setUp(() {
    now = DateTime.utc(2026);
    nextId = 0;
    storage = FakeStorage();
    executor = ControlledExecutor();
    cleanupErrors = [];
    service = create();
  });

  tearDown(() async {
    executor.releaseAll();
    await service.close();
  });

  test('limits reject invalid configurations', () {
    expect(() => JobLimits(maxConcurrentJobs: 0), throwsArgumentError);
    expect(() => JobLimits(maxQueuedJobs: -1), throwsArgumentError);
    expect(() => JobLimits(maxRetainedJobs: 1), throwsArgumentError);
    expect(() => JobLimits(jobTtl: Duration.zero), throwsArgumentError);
  });

  test(
    'admission reserves upload slots and does not double count retention',
    () async {
      service = create(
        limits: JobLimits(
          maxConcurrentJobs: 1,
          maxQueuedJobs: 1,
          maxRetainedJobs: 2,
        ),
      );
      final body = StreamController<List<int>>();
      final first = service.submit('first.xlog', body.stream);
      await storage.uploadStarted('id-0');
      final second = await submit('second.xlog');
      expect(second.status, JobStatus.queued);
      await expectLater(submit(), fails(ServiceError.queueFull));
      body.add([1]);
      await body.close();
      final uploaded = await first;
      expect(uploaded.status, JobStatus.queued);
      expect(executor.tasks, hasLength(1));
      executor.succeed(0);
      await executor.started(2);
      expect(executor.tasks[1].name, 'first.xlog');
      executor.succeed(1);
      expect((await terminal(service, uploaded.id)).status, JobStatus.success);
    },
  );

  test(
    'concurrency and FIFO queue obey limits; snapshots do not mutate',
    () async {
      service = create(
        limits: JobLimits(maxConcurrentJobs: 2, maxQueuedJobs: 2),
      );
      final jobs = <JobSnapshot>[];
      for (var i = 0; i < 4; i++) {
        jobs.add(await submit('$i.xlog'));
      }
      expect(executor.tasks.map((task) => task.name), ['0.xlog', '1.xlog']);
      await expectLater(submit(), fails(ServiceError.queueFull));
      executor.succeed(1);
      await executor.started(3);
      expect(executor.tasks[2].name, '2.xlog');
      executor.succeed(0);
      await executor.started(4);
      expect(executor.tasks[3].name, '3.xlog');
      expect(jobs.first.status, JobStatus.queued);
      executor.releaseAll();
    },
  );

  test(
    'queued delete cancels work; uploading and running delete are busy',
    () async {
      final running = await submit();
      await expectLater(
        service.delete(running.id),
        fails(ServiceError.jobBusy),
      );
      final queued = await submit('queued.xlog');
      final cancelled = await service.delete(queued.id);
      expect(cancelled.status, JobStatus.cancelled);
      expect(cancelled.finishedAt, now);
      await expectLater(
        service.get(queued.id),
        fails(ServiceError.jobNotFound),
      );
      final body = StreamController<List<int>>();
      final uploading = service.submit('upload.xlog', body.stream);
      await storage.uploadStarted('id-2');
      await expectLater(service.delete('id-2'), fails(ServiceError.jobBusy));
      body.add([1]);
      await body.close();
      await uploading;
      executor.succeed(0);
      await executor.started(2);
      expect(executor.tasks[1].name, 'upload.xlog');
    },
  );

  test('validation precedes storage and preserves filename rules', () async {
    await expectLater(submit('bad.txt'), fails(ServiceError.unsupportedFile));
    await expectLater(
      service.submit('a.xlog', Stream.value([1]), contentLength: 300000000),
      fails(ServiceError.uploadTooLarge),
    );
    await expectLater(submit('x' * 181), fails(ServiceError.invalidFilename));
    expect(storage.workspaces, isEmpty);
    final job = await submit(r'..\nested/hello world.XLOG');
    expect(job.name, 'hello world.XLOG');
  });

  test(
    'all candidate keys and execution budget pass through injected ports',
    () async {
      final keys = {
        'first': const ServerKey('First label', 'first-secret'),
        'second': const ServerKey('Second label', 'second-secret'),
      };
      service = create(keys: keys);
      keys.clear();
      final job = await service.submit('app.xlog', Stream.value([1]));
      final task = executor.tasks.single;
      expect(task.workspacePath, '/fake/${job.id}');
      expect(task.privateKeysHex, ['first-secret', 'second-secret']);
      expect(() => task.privateKeysHex.add('other'), throwsUnsupportedError);
      expect(task.maxOutputBytes, service.limits.maxOutputBytes);
      expect(storage.uploadLimit, service.limits.maxUploadBytes);
      expect(storage.uploadTimeout, service.limits.uploadTimeout);
    },
  );

  test(
    'upload failure removes admission reservation and preserves error',
    () async {
      final error = StateError('write failed');
      storage.uploadError = error;
      storage.cleanupError = StateError('cleanup failed');
      await expectLater(submit(), throwsA(same(error)));
      expect(executor.tasks, isEmpty);
      storage.uploadError = null;
      storage.cleanupError = null;
      final replacement = await submit();
      expect(replacement.status, JobStatus.queued);
    },
  );

  test('synchronous executor failure releases its running slot', () async {
    executor.synchronousError = StateError('cannot start executor');
    final failed = await submit();
    expect((await terminal(service, failed.id)).status, JobStatus.failure);
    executor.synchronousError = null;
    final next = await submit();
    await executor.started(1);
    expect((await service.get(next.id)).status, JobStatus.running);
  });

  test(
    'duplicate injected identifiers cannot overwrite existing jobs',
    () async {
      service = JobService(
        storage: storage,
        executor: executor,
        limits: JobLimits(maxConcurrentJobs: 1, maxQueuedJobs: 1),
        keys: const {},
        clock: () => now,
        idFactory: () => 'fixed-id',
      );
      final first = await submit('original.xlog');
      await expectLater(submit('replacement.xlog'), throwsStateError);
      expect((await service.get(first.id)).name, 'original.xlog');
      expect(executor.tasks, hasLength(1));
    },
  );

  test(
    'executor failure publishes no result; cleanup errors preserve success',
    () async {
      final first = await submit();
      final second = await submit('second.xlog');
      storage.cleanupError = StateError('workspace cleanup failed');
      executor.fail(0, StateError('decoder failed'));
      await executor.started(2);
      final failed = await service.get(first.id);
      expect(failed.status, JobStatus.failure);
      expect(failed.result, isNull);
      expect(failed.errorCode, 'decode_failed');
      expect(failed.finishedAt, now);
      await expectLater(
        service.download(first.id),
        fails(ServiceError.resultUnavailable),
      );
      storage.inputError = StateError('input cleanup failed');
      executor.succeed(1);
      final cleanupFailure = await terminal(service, second.id);
      expect(cleanupFailure.status, JobStatus.success);
      expect(cleanupFailure.result, isNotNull);
      expect(cleanupErrors, contains(storage.inputError));
      expect(cleanupErrors, contains(storage.cleanupError));
      final deleted = await service.delete(second.id);
      expect(deleted.status, JobStatus.cancelled);
      expect(deleted.result, isNull);
      await expectLater(
        service.get(second.id),
        fails(ServiceError.jobNotFound),
      );
    },
  );

  for (final names in {
    'app.xlog': 'app-decode.log',
    'archive.zip': 'archive-decode.zip',
    '设备 日志.XLOG': '设备 日志-decode.log',
    'app.release.bin': 'app.release-decode.log',
  }.entries) {
    test('download preserves the original name: ${names.key}', () async {
      final job = await submit(names.key);
      executor.succeed(0);
      await terminal(service, job.id);
      expect((await service.download(job.id)).filename, names.value);
    });
  }

  test('download checks availability and supports warning results', () async {
    final job = await submit();
    await expectLater(
      service.download(job.id),
      fails(ServiceError.resultUnavailable),
    );
    executor.succeed(0, issues: 1);
    expect((await terminal(service, job.id)).status, JobStatus.warning);
    final result = await service.download(job.id);
    expect(await result.openRead().toList(), [
      [7, 8],
    ]);
    storage.resultError = const ServiceException(ServiceError.resultExpired);
    await expectLater(
      service.download(job.id),
      fails(ServiceError.resultExpired),
    );
  });

  test(
    'concurrent TTL expiry deletes once and leaves unfinished jobs',
    () async {
      final first = await submit();
      executor.succeed(0);
      await terminal(service, first.id);
      final running = await submit('running.xlog');
      now = now.add(const Duration(hours: 2));
      final deletionGate = Completer<void>();
      storage.deletionGate = deletionGate;
      final expiry = service.expire();
      await storage.deletionStarted(first.id);
      await service.expire();
      await expectLater(service.get(first.id), fails(ServiceError.jobNotFound));
      expect((await service.get(running.id)).status, JobStatus.running);
      expect(storage.deletions.where((id) => id == first.id), hasLength(1));
      deletionGate.complete();
      await expiry;
    },
  );

  test(
    'TTL does not delete while a download stream is being listened to',
    () async {
      final job = await submit();
      executor.succeed(0);
      await terminal(service, job.id);
      final stream = StreamController<List<int>>();
      storage.resultStream = () => stream.stream;
      final result = await service.download(job.id);
      final firstChunk = Completer<void>();
      final subscription = result.openRead().listen(
        (_) => firstChunk.complete(),
      );
      stream.add([1]);
      await firstChunk.future;
      now = now.add(const Duration(hours: 2));
      await service.expire();
      expect(storage.deletions, isEmpty);
      await subscription.cancel();
      await stream.close();
      await service.expire();
      expect(storage.deletions, [job.id]);
    },
  );

  test(
    'close is idempotent, waits for uploads/workers and rejects admission',
    () async {
      service = create(
        limits: JobLimits(maxConcurrentJobs: 1, maxQueuedJobs: 2),
      );
      final running = await submit();
      final queued = await submit('queued.xlog');
      final body = StreamController<List<int>>();
      final upload = service.submit('upload.xlog', body.stream);
      await storage.uploadStarted('id-2');
      var closed = false;
      final closing = service.close().then((_) => closed = true);
      expect(identical(service.close(), service.close()), isTrue);
      await expectLater(submit(), fails(ServiceError.serviceClosed));
      expect(closed, isFalse);
      expect((await service.get(queued.id)).status, JobStatus.cancelled);
      executor.succeed(0);
      await terminal(service, running.id);
      expect(closed, isFalse);
      body.add([1]);
      await body.close();
      expect((await upload).status, JobStatus.cancelled);
      await closing;
      expect(executor.tasks, hasLength(1));
      expect(storage.workspaces, isEmpty);
      await expectLater(
        service.get(running.id),
        fails(ServiceError.jobNotFound),
      );
    },
  );

  test(
    'simultaneous submissions stay bounded and keep independent results',
    () async {
      service = create(
        limits: JobLimits(maxConcurrentJobs: 3, maxQueuedJobs: 5),
      );
      final outcomes = await Future.wait([
        for (var i = 0; i < 20; i++)
          submit(
            'client-$i.xlog',
          ).then<Object>((job) => job, onError: (Object error) => error),
      ]);
      final accepted = outcomes.whereType<JobSnapshot>().toList();
      final rejected = outcomes.whereType<ServiceException>().toList();
      expect(accepted, hasLength(8));
      expect(rejected, hasLength(12));
      expect(
        rejected.map((error) => error.error),
        everyElement(ServiceError.queueFull),
      );
      expect(executor.tasks, hasLength(3));
      executor.fail(1, StateError('one client supplied a corrupt file'));
      await executor.started(4);
      executor.succeed(0, outputBytes: 1, filename: 'client-0.log');
      await executor.started(5);
      for (var i = 2; i < 8; i++) {
        executor.succeed(i, outputBytes: i + 1, filename: 'client-$i.log');
        if (i < 5) await executor.started(i + 4);
      }
      expect(executor.maxActive, 3);
      expect(executor.tasks.map((task) => task.name), [
        for (var i = 0; i < 8; i++) 'client-$i.xlog',
      ]);
      for (var i = 0; i < accepted.length; i++) {
        final job = await terminal(service, accepted[i].id);
        expect(job.status, i == 1 ? JobStatus.failure : JobStatus.success);
        if (i == 1) {
          expect(job.result, isNull);
        } else {
          expect(job.result!.filename, 'client-$i.log');
          expect(job.result!.outputBytes, i + 1);
          storage.resultBytes[job.id] = [i];
        }
      }
      final first = accepted[0];
      final other = accepted[2];
      final downloads = await Future.wait([
        service.download(first.id),
        service.download(other.id),
      ]);
      expect(
        await Future.wait(
          downloads.map((result) => result.openRead().toList()),
        ),
        [
          [
            [0],
          ],
          [
            [2],
          ],
        ],
      );
    },
  );

  test(
    'a burst of unfinished uploads reserves capacity before any body completes',
    () async {
      service = create(
        limits: JobLimits(maxConcurrentJobs: 2, maxQueuedJobs: 2),
      );
      final bodies = [
        for (var i = 0; i < 12; i++) StreamController<List<int>>(),
      ];
      final outcomes = [
        for (var i = 0; i < bodies.length; i++)
          service
              .submit('client-$i.xlog', bodies[i].stream)
              .then<Object>((job) => job, onError: (Object error) => error),
      ];
      await storage.uploadStarted('id-3');
      expect(executor.tasks, isEmpty);
      final rejected = await Future.wait(outcomes.skip(4));
      expect(
        rejected,
        everyElement(
          isA<ServiceException>().having(
            (error) => error.error,
            'error',
            ServiceError.queueFull,
          ),
        ),
      );
      for (var i = 3; i >= 0; i--) {
        bodies[i].add([i]);
        await bodies[i].close();
        expect(await outcomes[i], isA<JobSnapshot>());
      }
      expect(executor.tasks.map((task) => task.name), [
        'client-3.xlog',
        'client-2.xlog',
      ]);
      executor.succeed(0);
      await executor.started(3);
      executor.succeed(1);
      await executor.started(4);
      expect(executor.tasks.map((task) => task.name), [
        'client-3.xlog',
        'client-2.xlog',
        'client-1.xlog',
        'client-0.xlog',
      ]);
      expect(executor.maxActive, 2);
      for (final body in bodies.skip(4)) {
        // Rejected bodies were never listened to; closing them must not be awaited.
        unawaited(body.close());
      }
    },
  );

  test(
    'a failed worker remains busy until its cleanup releases the slot',
    () async {
      final running = await submit();
      await submit('next.xlog');
      final gate = Completer<void>();
      storage.deletionGate = gate;
      executor.fail(0, StateError('decode failed'));
      await storage.deletionStarted(running.id);
      expect((await service.get(running.id)).status, JobStatus.running);
      await expectLater(
        service.delete(running.id),
        fails(ServiceError.jobBusy),
      );
      expect(executor.tasks, hasLength(1));
      expect(storage.deletions, [running.id]);
      gate.complete();
      await executor.started(2);
      expect((await service.get(running.id)).status, JobStatus.failure);
    },
  );

  test(
    'deleting during result lookup revokes the pending download before returning it',
    () async {
      final job = await submit();
      executor.succeed(0);
      await terminal(service, job.id);
      final gate = Completer<void>();
      storage.resultGate = gate;
      final download = service.download(job.id);
      final rejectedDownload = expectLater(
        download,
        fails(ServiceError.resultExpired),
      );
      await storage.resultReadStarted(job.id);
      expect((await service.delete(job.id)).status, JobStatus.cancelled);
      expect(storage.deletions, isEmpty);
      await expectLater(service.get(job.id), fails(ServiceError.jobNotFound));
      gate.complete();
      await rejectedDownload;
      await storage.deletionStarted(job.id);
      expect(storage.deletions, [job.id]);
    },
  );

  test(
    'DELETE removes results immediately and retains active readers safely',
    () async {
      service = create(
        limits: JobLimits(
          maxConcurrentJobs: 1,
          maxQueuedJobs: 0,
          maxRetainedJobs: 1,
        ),
      );
      final job = await submit();
      executor.succeed(0);
      await terminal(service, job.id);
      final listening = [Completer<void>(), Completer<void>()];
      final streams = [
        for (var i = 0; i < 2; i++)
          StreamController<List<int>>(onListen: () => listening[i].complete()),
      ];
      var reader = 0;
      storage.resultStream = () => streams[reader++].stream;
      final results = await Future.wait([
        service.download(job.id),
        service.download(job.id),
      ]);
      final subscriptions = [
        for (final result in results) result.openRead().listen((_) {}),
      ];
      await Future.wait(listening.map((event) => event.future));
      expect((await service.delete(job.id)).status, JobStatus.cancelled);
      await expectLater(
        service.download(job.id),
        fails(ServiceError.jobNotFound),
      );
      await service.expire();
      expect(storage.deletions, isEmpty);
      await expectLater(submit(), fails(ServiceError.queueFull));
      await subscriptions[0].cancel();
      expect(storage.deletions, isEmpty);
      await subscriptions[1].cancel();
      await storage.deletionStarted(job.id);
      for (final stream in streams) {
        await stream.close();
      }
      expect((await submit('replacement.xlog')).status, JobStatus.queued);
      expect(storage.deletions, [job.id]);
    },
  );

  test(
    'simultaneous expiry, reads, deletes and close clean each workspace once',
    () async {
      service = create(
        limits: JobLimits(maxConcurrentJobs: 3, maxQueuedJobs: 3),
      );
      final jobs = await Future.wait([
        for (var i = 0; i < 6; i++) submit('$i.xlog'),
      ]);
      for (var i = 0; i < 6; i++) {
        executor.succeed(i);
        if (i < 3) await executor.started(i + 4);
      }
      await Future.wait(jobs.map((job) => terminal(service, job.id)));
      now = now.add(const Duration(hours: 2));
      final gate = Completer<void>();
      storage.deletionGate = gate;
      final expirations = [for (var i = 0; i < 10; i++) service.expire()];
      await storage.deletionStarted(jobs.last.id);
      await Future.wait([
        for (final job in jobs) ...[
          expectLater(service.get(job.id), fails(ServiceError.jobNotFound)),
          expectLater(service.delete(job.id), fails(ServiceError.jobNotFound)),
        ],
      ]);
      final closing = service.close();
      gate.complete();
      await Future.wait([...expirations, closing]);
      expect(storage.deletions.toSet(), jobs.map((job) => job.id).toSet());
      expect(storage.deletions, hasLength(6));
    },
  );

  test(
    'shutdown does not wait for a pending result lookup or an active stream',
    () async {
      final job = await submit();
      executor.succeed(0);
      await terminal(service, job.id);
      final listening = Completer<void>();
      final stream = StreamController<List<int>>(onListen: listening.complete);
      storage.resultStream = () => stream.stream;
      final result = await service.download(job.id);
      final subscription = result.openRead().listen((_) {});
      await listening.future;
      final gate = Completer<void>();
      storage.resultGate = gate;
      final pending = expectLater(
        service.download(job.id),
        fails(ServiceError.resultExpired),
      );
      await storage.resultReadStarted(job.id, count: 2);
      await service.close();
      expect(storage.workspaces, isEmpty);
      gate.complete();
      await pending;
      await subscription.cancel();
      await stream.close();
      expect(storage.deletions, [job.id]);
    },
  );
}

Matcher fails(ServiceError error) => throwsA(
  isA<ServiceException>().having(
    (exception) => exception.error,
    'error',
    error,
  ),
);

// The fake ports complete through microtasks, so this has no wall-clock sleeps.
Future<JobSnapshot> terminal(JobService service, String id) async {
  for (var i = 0; i < 100; i++) {
    final job = await service.get(id);
    if (job.finishedAt != null) return job;
  }
  throw StateError('Job did not finish');
}

class ControlledExecutor implements JobExecutor {
  final tasks = <DecodeTask>[];
  Object? synchronousError;
  final _results = <Completer<DecodeResult>>[];
  final _started = <int, Completer<void>>{};
  var _active = 0;
  var maxActive = 0;

  @override
  Future<DecodeResult> execute(DecodeTask task) {
    if (synchronousError case final error?) throw error;
    tasks.add(task);
    _active++;
    if (_active > maxActive) maxActive = _active;
    final result = Completer<DecodeResult>();
    _results.add(result);
    _started.remove(tasks.length)?.complete();
    return result.future;
  }

  Future<void> started(int count) => tasks.length >= count
      ? Future.value()
      : (_started[count] ??= Completer<void>()).future;

  void succeed(
    int index, {
    int issues = 0,
    int outputBytes = 2,
    String filename = 'result.log',
  }) {
    _active--;
    _results[index].complete(
      DecodeResult(
        filename: filename,
        outputBytes: outputBytes,
        blockCount: 1,
        issueCount: issues,
      ),
    );
  }

  void fail(int index, Object error) {
    _active--;
    _results[index].completeError(error);
  }

  void releaseAll() {
    for (var i = 0; i < _results.length; i++) {
      if (!_results[i].isCompleted) succeed(i);
    }
  }
}

class FakeStorage implements JobStorage {
  final workspaces = <String>{};
  final deletions = <String>[];
  final _uploadStarted = <String, Completer<void>>{};
  final _deletionStarted = <String, Completer<void>>{};
  final _uploads = <String>{};
  final resultBytes = <String, List<int>>{};
  final _resultReads = <String, int>{};
  final _resultReadStarted = <(String, int), Completer<void>>{};
  Object? uploadError, cleanupError, inputError, resultError;
  Completer<void>? deletionGate;
  Completer<void>? resultGate;
  Stream<List<int>> Function()? resultStream;
  int? uploadLimit;
  Duration? uploadTimeout;

  Future<void> resultReadStarted(String id, {int count = 1}) =>
      (_resultReads[id] ?? 0) >= count
      ? Future.value()
      : (_resultReadStarted[(id, count)] ??= Completer<void>()).future;

  Future<void> uploadStarted(String id) => _uploads.contains(id)
      ? Future.value()
      : (_uploadStarted[id] ??= Completer<void>()).future;

  Future<void> deletionStarted(String id) => deletions.contains(id)
      ? Future.value()
      : (_deletionStarted[id] ??= Completer<void>()).future;

  @override
  Future<void> initialize() async {}

  @override
  Future<String> createWorkspace(String id) async {
    workspaces.add(id);
    return '/fake/$id';
  }

  @override
  Future<void> writeUpload(
    String id,
    Stream<List<int>> source, {
    required int maxBytes,
    required Duration timeout,
  }) async {
    _uploads.add(id);
    _uploadStarted.remove(id)?.complete();
    uploadLimit = maxBytes;
    uploadTimeout = timeout;
    if (uploadError case final error?) throw error;
    var length = 0;
    await for (final chunk in source) {
      length += chunk.length;
      if (length > maxBytes) {
        throw const ServiceException(ServiceError.uploadTooLarge);
      }
    }
    if (length == 0) throw const ServiceException(ServiceError.emptyUpload);
  }

  @override
  Future<void> deleteWorkspace(String id) async {
    deletions.add(id);
    _deletionStarted.remove(id)?.complete();
    if (deletionGate case final gate?) await gate.future;
    if (cleanupError case final error?) throw error;
    workspaces.remove(id);
  }

  @override
  Future<void> deleteInput(String id) async {
    if (inputError case final error?) throw error;
  }

  @override
  Future<StoredResult> readResult(String id, String filename) async {
    final count = (_resultReads[id] ?? 0) + 1;
    _resultReads[id] = count;
    _resultReadStarted.remove((id, count))?.complete();
    if (resultGate case final gate?) await gate.future;
    if (resultError case final error?) throw error;
    return StoredResult(
      filename: filename,
      length: 2,
      openRead: resultStream ?? () => Stream.value(resultBytes[id] ?? [7, 8]),
    );
  }
}
