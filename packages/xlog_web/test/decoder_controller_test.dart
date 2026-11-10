import 'dart:async';

import 'package:test/test.dart';
import 'package:xlog_web/features/decoder/application/decoder_controller.dart';
import 'package:xlog_web/features/decoder/application/decoder_state.dart';
import 'package:xlog_web/features/decoder/domain/decoder_api.dart';
import 'package:xlog_web/features/decoder/domain/models.dart';

void main() {
  late _FakeApi api;
  late DecoderController controller;

  setUp(() {
    api = _FakeApi();
    controller = DecoderController(
      baseUri: Uri.parse('https://decoder.example/'),
      createApi: (_) => api,
      pollInterval: const Duration(milliseconds: 5),
    );
  });

  tearDown(() => controller.dispose());

  test(
    'initialization uses deployment endpoint and publishes immutable snapshots',
    () async {
      Uri? endpoint;
      controller.dispose();
      controller = DecoderController(
        baseUri: Uri.parse('https://decoder.example/base'),
        createApi: (uri) {
          endpoint = uri;
          return api;
        },
      );
      final before = controller.state;
      final states = <DecoderState>[];
      final subscription = controller.changes.listen(states.add);
      api.limit = 123;
      await controller.initialize();
      await pumpEventQueue();

      expect(endpoint.toString(), 'https://decoder.example/base/');
      expect(controller.state.maxUploadBytes, 123);
      expect(controller.state.ready, isTrue);
      expect(controller.state.initializing, isFalse);
      expect(states.any((state) => state.initializing), isTrue);
      expect(before.ready, isFalse);
      expect(before.jobs, isEmpty);
      expect(() => controller.state.jobs.clear(), throwsUnsupportedError);
      await subscription.cancel();
    },
  );

  test('rejects invalid deployment endpoints before creating a client', () {
    for (final address in [
      'not an address',
      'ftp://decoder.example/',
      'https://user:secret@decoder.example/',
      'https://decoder.example/?unexpected=query',
      'https://decoder.example/#fragment',
    ]) {
      expect(
        () => DecoderController(
          baseUri: Uri.parse(address),
          createApi: (_) => api,
        ),
        throwsArgumentError,
      );
    }
    expect(api.healthCalls, 0);
  });

  test(
    'service failure is retryable without changing any configuration',
    () async {
      api.onHealth = () => throw const ApiException('network');
      await controller.initialize();
      expect(controller.state.errorKey, 'error_network');
      expect(controller.state.initializing, isFalse);
      expect(controller.state.ready, isFalse);
      expect(api.closeCalls, 1);

      api.onHealth = null;
      await controller.initialize();
      expect(controller.state.ready, isTrue);
      expect(controller.state.errorKey, isNull);
      expect(api.healthCalls, 2);
    },
  );

  test(
    'initialization guards duplicate retries and disposal during health',
    () async {
      final health = Completer<int>();
      api.onHealth = () => health.future;
      final connection = controller.initialize();
      await controller.initialize();
      expect(api.healthCalls, 1);

      final disposedState = controller.state;
      controller.dispose();
      health.complete(123);
      await connection;
      expect(controller.state, same(disposedState));
      expect(api.closeCalls, 1);
      await expectLater(controller.changes, emitsDone);
    },
  );

  test(
    'refresh updates upload limits and closes the previous client',
    () async {
      final next = _FakeApi();
      var useNext = false;
      controller.dispose();
      api = _FakeApi();
      controller = DecoderController(
        baseUri: Uri.parse('https://decoder.example/'),
        createApi: (_) => useNext ? next : api,
      );
      await controller.initialize();
      useNext = true;
      await controller.initialize();
      expect(api.closeCalls, 1);

      next.limit = 456;
      await controller.initialize();
      expect(controller.state.maxUploadBytes, 456);
      expect(next.closeCalls, 0);
    },
  );

  test(
    'uploads files directly, rejects oversized files and continues after errors',
    () async {
      api.limit = 10;
      await controller.initialize();
      final progress = <JobEntry>[];
      api.onUpload = (file, onProgress) async {
        onProgress(0.5);
        progress.add(controller.state.jobs.first);
        if (file.name == 'broken') {
          throw StateError('unexpected transport error');
        }
        return _job(file.name, status: 'success');
      };
      await controller.upload(const [
        _File('too-big', 11),
        _File('broken', 1),
        _File('valid', 10),
      ]);

      expect(api.uploads, ['broken', 'valid']);
      expect(controller.state.jobs.map((job) => job.name), [
        'valid',
        'broken',
        'too-big',
      ]);
      expect(controller.state.jobs.map((job) => job.status), [
        'success',
        'failure',
        'failure',
      ]);
      expect(controller.state.jobs[1].errorKey, 'error_unknown');
      expect(controller.state.jobs[2].errorKey, 'fileTooLarge');
      expect(controller.state.jobs.first.download, '/download/valid');
      expect(progress.first.progress, 0.5);
      expect(progress.first.status, 'uploading');
      expect(controller.state.uploading, isFalse);
      expect(controller.state.busy, isFalse);
      expect(
        controller.state.jobs.map((job) => job.localId).toSet(),
        hasLength(3),
      );
    },
  );

  test(
    'requires readiness and guards an entire active batch and pending jobs',
    () async {
      await controller.upload(const [_File('before-ready', 1)]);
      expect(controller.state.errorKey, 'serviceUnavailable');
      await controller.initialize();
      final upload = Completer<RemoteJob>();
      api.onUpload = (_, _) => upload.future;
      final batch = controller.upload(const [_File('pending', 1)]);
      final before = controller.state;

      void tryEdits() {
        controller.clearHistory();
      }

      tryEdits();
      await controller.upload(const [_File('ignored-batch', 1)]);
      await controller.initialize();
      expect(controller.state, same(before));
      expect(api.uploads, hasLength(1));
      expect(api.healthCalls, 1);
      upload.complete(_job('pending'));
      await batch;
      expect(controller.state.busy, isTrue);
      final queued = controller.state;
      tryEdits();
      expect(controller.state, same(queued));

      await controller.cancel(controller.state.jobs.single);
      expect(controller.state.busy, isFalse);
      tryEdits();
      expect(controller.state.jobs, isEmpty);
    },
  );

  test('caps history at fifty and lets completed history be cleared', () async {
    await controller.initialize();
    await controller.upload(List.generate(51, (index) => _File('$index', 1)));
    expect(controller.state.jobs, hasLength(50));
    expect(api.uploads, hasLength(50));
    expect(controller.state.errorKey, 'historyFull');
    expect(controller.state.uploading, isFalse);
    final history = controller.state;
    controller.clearHistory();
    expect(controller.state.jobs, isEmpty);
    expect(history.jobs, hasLength(50));
  });

  test(
    'polls through transient errors, clears recovered errors and stops at completion',
    () async {
      await controller.initialize();
      api.onUpload = (file, _) => _job(file.name);
      var calls = 0;
      api.onJob = (id) {
        calls++;
        if (calls == 1) throw const ApiException('network');
        return _job(id, status: calls == 2 ? 'running' : 'warning');
      };
      await controller.upload(const [_File('polling', 1)]);
      await _waitFor(controller, (state) => state.errorKey == 'error_network');
      expect(controller.state.jobs.single.finished, isFalse);
      await _waitFor(
        controller,
        (state) => state.jobs.single.status == 'running',
      );
      await _waitFor(controller, (state) => state.errorKey == null);
      await _waitFor(controller, (state) => state.jobs.single.finished);
      expect(controller.state.jobs.single.status, 'warning');
      expect(controller.state.busy, isFalse);
      await Future<void>.delayed(const Duration(milliseconds: 25));
      expect(calls, 3);
    },
  );

  test('terminal poll errors finish jobs and stop retries', () async {
    await controller.initialize();
    api.onUpload = (file, _) => _job(file.name);
    api.onJob = (_) => throw const ApiException('not_found');
    await controller.upload(const [_File('expired', 1)]);
    await _waitFor(controller, (state) => state.jobs.single.finished);
    expect(controller.state.jobs.single.status, 'failure');
    expect(controller.state.jobs.single.errorKey, 'error_not_found');
    await Future<void>.delayed(const Duration(milliseconds: 25));
    expect(api.jobCalls, 1);
  });

  test('cancellation wins over an earlier in-flight poll response', () async {
    await controller.initialize();
    api.onUpload = (file, _) => _job(file.name);
    final poll = Completer<RemoteJob>();
    final started = Completer<void>();
    api.onJob = (_) {
      started.complete();
      return poll.future;
    };
    await controller.upload(const [_File('queued', 1)]);
    await started.future.timeout(const Duration(seconds: 2));
    await controller.cancel(controller.state.jobs.single);
    expect(api.cancellations, ['queued']);
    expect(controller.state.jobs.single.status, 'cancelled');
    poll.complete(_job('queued', status: 'running'));
    await pumpEventQueue();
    expect(controller.state.jobs.single.status, 'cancelled');
    await Future<void>.delayed(const Duration(milliseconds: 25));
    expect(api.jobCalls, 1);
  });

  test('cancel errors remain actionable while polling can continue', () async {
    await controller.initialize();
    api.onUpload = (file, _) => _job(file.name);
    api.onCancel = (_) => throw const ApiException('not_cancellable');
    await controller.upload(const [_File('queued', 1)]);
    await controller.cancel(controller.state.jobs.single);
    expect(controller.state.errorKey, 'error_not_cancellable');
    expect(controller.state.jobs.single.status, 'queued');
  });

  test(
    'disposal ignores late upload progress/results and stops the batch',
    () async {
      await controller.initialize();
      final upload = Completer<RemoteJob>();
      late void Function(double) progress;
      api.onUpload = (_, onProgress) {
        progress = onProgress;
        return upload.future;
      };
      final batch = controller.upload(const [
        _File('first', 1),
        _File('never', 1),
      ]);
      final disposedState = controller.state;
      controller.dispose();
      progress(0.9);
      upload.complete(_job('first'));
      await batch;
      await controller.initialize();
      await controller.cancel(disposedState.jobs.single);
      expect(controller.state, same(disposedState));
      expect(api.uploads, hasLength(1));
      expect(api.jobCalls, 0);
      expect(api.closeCalls, 1);
      await expectLater(controller.changes, emitsDone);
    },
  );

  test(
    'disposal ignores an in-flight poll and closes its stream once',
    () async {
      await controller.initialize();
      api.onUpload = (file, _) => _job(file.name);
      final poll = Completer<RemoteJob>();
      final started = Completer<void>();
      api.onJob = (_) {
        started.complete();
        return poll.future;
      };
      await controller.upload(const [_File('queued', 1)]);
      await started.future.timeout(const Duration(seconds: 2));
      final disposedState = controller.state;
      controller.dispose();
      controller.dispose();
      poll.complete(_job('queued', status: 'success'));
      await pumpEventQueue();
      expect(controller.state, same(disposedState));
      expect(api.closeCalls, 1);
      await expectLater(controller.changes, emitsDone);
    },
  );
}

Future<void> _waitFor(
  DecoderController controller,
  bool Function(DecoderState) predicate,
) async {
  if (predicate(controller.state)) return;
  await controller.changes
      .firstWhere(predicate)
      .timeout(const Duration(seconds: 2));
}

RemoteJob _job(String id, {String status = 'queued'}) => RemoteJob(
  id: id,
  name: id,
  status: status,
  downloadUrl: status == 'success' ? '/download/$id' : null,
);

class _File implements UploadFile {
  const _File(this.name, this.size);
  @override
  final String name;
  @override
  final int size;
}

class _FakeApi implements DecoderApi {
  int limit = 100;
  int healthCalls = 0;
  int jobCalls = 0;
  int closeCalls = 0;
  final uploads = <String>[];
  final cancellations = <String>[];
  FutureOr<int> Function()? onHealth;
  FutureOr<RemoteJob> Function(String)? onJob;
  FutureOr<void> Function(String)? onCancel;
  FutureOr<RemoteJob> Function(UploadFile, void Function(double))? onUpload;

  @override
  Future<int> health() async {
    healthCalls++;
    return onHealth == null ? limit : await onHealth!();
  }

  @override
  Future<RemoteJob> job(String id) async {
    jobCalls++;
    return onJob == null ? _job(id, status: 'success') : await onJob!(id);
  }

  @override
  Future<void> cancel(String id) async {
    cancellations.add(id);
    await onCancel?.call(id);
  }

  @override
  Future<RemoteJob> upload(
    UploadFile file, {
    required void Function(double) onProgress,
  }) async {
    uploads.add(file.name);
    if (onUpload != null) return await onUpload!(file, onProgress);
    return _job(file.name, status: 'success');
  }

  @override
  String? downloadLink(RemoteJob job) => job.downloadUrl;

  @override
  void close() => closeCalls++;
}
