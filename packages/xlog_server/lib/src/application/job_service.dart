import 'dart:async';
import 'dart:collection';
import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:logging/logging.dart';
import 'package:xlog_decode/xlog_decode.dart';

import '../diagnostics/server_logging.dart';

import '../domain/decode_task.dart';
import '../domain/job_snapshot.dart';
import '../domain/job_status.dart';
import '../domain/server_key.dart';
import '../domain/service_exception.dart';
import '../domain/stored_result.dart';
import 'job_limits.dart';
import 'job_record.dart';
import 'ports/job_executor.dart';
import 'ports/job_storage.dart';

final _log = Logger('xlog.jobs');

/// Coordinates bounded uploads and decoding without depending on a transport
/// or a particular filesystem/execution mechanism.
class JobService {
  JobService({
    required JobStorage storage,
    required JobExecutor executor,
    required this.limits,
    required Map<String, ServerKey> keys,
    DateTime Function()? clock,
    String Function()? idFactory,
    void Function(Object error, StackTrace stack)? onCleanupError,
  }) : _storage = storage,
       _executor = executor,
       _privateKeysHex = List.unmodifiable(
         keys.values.map((key) => key.privateKeyHex),
       ),
       _clock = clock ?? DateTime.now,
       _idFactory = idFactory ?? _randomId,
       _onCleanupError = onCleanupError;

  final JobStorage _storage;
  final JobExecutor _executor;
  final JobLimits limits;
  final List<String> _privateKeysHex;
  final DateTime Function() _clock;
  final String Function() _idFactory;
  final void Function(Object error, StackTrace stack)? _onCleanupError;
  final _jobs = <String, JobRecord>{};
  // Revoked jobs retain their workspace only while an existing reader uses it.
  final _retired = <String, JobRecord>{};
  final _deletions = <String, Future<void>>{};
  final _queue = Queue<JobRecord>();
  final _uploads = <Future<void>>{};
  final _workers = <Future<void>>{};
  final _cleanups = <Future<void>>{};
  int _uploading = 0;
  int _running = 0;
  bool _closed = false;
  Future<void>? _closeFuture;

  Future<JobSnapshot> submit(
    String name,
    Stream<List<int>> body, {
    int? contentLength,
  }) {
    if (_closed) {
      return Future.error(const ServiceException(ServiceError.serviceClosed));
    }
    final operation = _submit(name, body, contentLength);
    _track(operation, _uploads);
    return operation;
  }

  Future<JobSnapshot> _submit(
    String name,
    Stream<List<int>> body,
    int? contentLength,
  ) async {
    await expire();
    if (_closed) throw const ServiceException(ServiceError.serviceClosed);
    if (_running + _uploading + _queue.length >=
            limits.maxConcurrentJobs + limits.maxQueuedJobs ||
        _jobs.length + _retired.length >= limits.maxRetainedJobs) {
      throw const ServiceException(ServiceError.queueFull);
    }
    final safeName = _safeName(name);
    if (!const [
      '.xlog',
      '.log',
      '.bin',
      '.zip',
    ].contains(p.extension(safeName).toLowerCase())) {
      throw const ServiceException(ServiceError.unsupportedFile);
    }
    if ((contentLength ?? 0) > limits.maxUploadBytes) {
      throw const ServiceException(ServiceError.uploadTooLarge);
    }

    final id = _idFactory();
    if (_jobs.containsKey(id) ||
        _retired.containsKey(id) ||
        _deletions.containsKey(id)) {
      throw StateError('Duplicate job identifier');
    }
    final job = JobRecord(id, safeName);
    _jobs[id] = job;
    _uploading++;
    _log.info({
      'event': 'job.upload.started',
      'jobId': id,
      'inputBytes': contentLength,
    });
    try {
      job.workspacePath = await _storage.createWorkspace(id);
      await _storage.writeUpload(
        id,
        body,
        maxBytes: limits.maxUploadBytes,
        timeout: limits.uploadTimeout,
      );
      if (_closed) {
        job.status = JobStatus.cancelled;
        job.finishedAt = _clock();
      } else {
        job.status = JobStatus.queued;
        _queue.add(job);
        _log.info({'event': 'job.queued', 'jobId': id});
      }
      // Capture admission status before scheduling can mutate the record.
      return job.snapshot();
    } catch (error, stack) {
      logFailure(
        _log,
        Level.WARNING,
        'job.upload.failed',
        error,
        stack,
        fields: {'jobId': id},
      );
      _jobs.remove(id);
      await _cleanup(id);
      rethrow;
    } finally {
      _uploading--;
      _schedule();
    }
  }

  Future<JobSnapshot> get(String id) async {
    await expire();
    return _find(id).snapshot();
  }

  Future<JobSnapshot> delete(String id) async {
    await expire();
    final job = _find(id);
    if (job.status == JobStatus.running || job.status == JobStatus.uploading) {
      throw const ServiceException(ServiceError.jobBusy);
    }
    _queue.remove(job);
    _jobs.remove(id);
    job.status = JobStatus.cancelled;
    job.finishedAt = _clock();
    job.result = null;
    _retired[id] = job;
    _log.info({'event': 'job.deleted', 'jobId': id});
    if (job.readers == 0) await _cleanupRetired(job);
    return job.snapshot();
  }

  Future<StoredResult> download(String id) async {
    await expire();
    final job = _find(id);
    if (job.result == null ||
        (job.status != JobStatus.success && job.status != JobStatus.warning)) {
      throw const ServiceException(ServiceError.resultUnavailable);
    }
    job.readers++;
    try {
      final result = await _storage.readResult(id, job.result!.filename);
      // DELETE/close can revoke a job while storage metadata is being read.
      if (!identical(_jobs[id], job)) {
        throw const ServiceException(ServiceError.resultExpired);
      }
      return StoredResult(
        filename:
            '${p.posix.basenameWithoutExtension(job.name)}-decode${p.extension(job.name).toLowerCase() == '.zip' ? '.zip' : '.log'}',
        length: result.length,
        openRead: () => _read(job, result),
      );
    } finally {
      _releaseReader(job);
    }
  }

  Stream<List<int>> _read(JobRecord job, StoredResult result) async* {
    // A result not listened to before its TTL may already have expired.
    if (!identical(_jobs[job.id], job)) {
      throw const ServiceException(ServiceError.resultExpired);
    }
    job.readers++;
    try {
      yield* result.openRead();
    } finally {
      _releaseReader(job);
    }
  }

  Future<void> expire() async {
    final cutoff = _clock().subtract(limits.jobTtl);
    final expired = _jobs.values
        .where(
          (job) =>
              job.readers == 0 &&
              job.finishedAt != null &&
              job.finishedAt!.isBefore(cutoff),
        )
        .toList();
    // Remove every candidate before any asynchronous deletion can interleave.
    for (final job in expired) {
      _jobs.remove(job.id);
      _retired[job.id] = job;
      _log.fine({'event': 'job.expired', 'jobId': job.id});
    }
    await Future.wait(expired.map(_cleanupRetired));
  }

  Future<void> close() => _closeFuture ??= _close();

  Future<void> _close() async {
    _closed = true;
    for (final job in _queue) {
      job.status = JobStatus.cancelled;
      job.finishedAt = _clock();
    }
    _queue.clear();
    await Future.wait(_uploads.toList());
    await Future.wait(_workers.toList());
    _retired.addAll(_jobs);
    _jobs.clear();
    // Shutdown force-cleans active downloads too; it never waits for a caller
    // to start or finish listening to a result stream.
    await Future.wait(_retired.values.toList().map(_cleanupRetired));
    // Includes deletions already started by expire/delete before shutdown.
    await Future.wait(_cleanups.toList());
  }

  JobRecord _find(String id) =>
      _jobs[id] ?? (throw const ServiceException(ServiceError.jobNotFound));

  void _schedule() {
    while (!_closed &&
        _running < limits.maxConcurrentJobs &&
        _queue.isNotEmpty) {
      final job = _queue.removeFirst();
      job.status = JobStatus.running;
      _running++;
      final operation = _run(job);
      final completion = operation.whenComplete(() {
        _running--;
        _schedule();
      });
      _track(completion, _workers);
    }
  }

  Future<void> _run(JobRecord job) async {
    final watch = Stopwatch()..start();
    _log.info({'event': 'job.started', 'jobId': job.id});
    try {
      final result = await _executor.execute(
        DecodeTask(
          workspacePath: job.workspacePath!,
          name: job.name,
          privateKeysHex: _privateKeysHex,
          maxOutputBytes: limits.maxOutputBytes,
        ),
      );
      await _bestEffort(() => _storage.deleteInput(job.id), jobId: job.id);
      job.result = result;
      job.status = result.issueCount > 0
          ? JobStatus.warning
          : JobStatus.success;
      _log.log(result.issueCount > 0 ? Level.WARNING : Level.INFO, {
        'event': 'job.completed',
        'jobId': job.id,
        'durationMs': watch.elapsedMilliseconds,
        'outputBytes': result.outputBytes,
        'blockCount': result.blockCount,
        'issueCount': result.issueCount,
      });
    } catch (error, stack) {
      logFailure(
        _log,
        Level.WARNING,
        'job.failed',
        error,
        stack,
        fields: {
          'jobId': job.id,
          'durationMs': watch.elapsedMilliseconds,
          if (error is XlogKeySelectionException) 'reason': error.reason.name,
          if (error is XlogResourceLimitException) 'resource': error.resource,
        },
      );
      job.result = null;
      await _cleanup(job.id);
      job.status = JobStatus.failure;
      job.errorCode = 'decode_failed';
    } finally {
      job.finishedAt = _clock();
    }
  }

  Future<void> _cleanup(String id) {
    final existing = _deletions[id];
    if (existing != null) return existing;
    final operation = _bestEffort(
      () => _storage.deleteWorkspace(id),
      jobId: id,
    );
    _deletions[id] = operation;
    _track(operation, _cleanups);
    unawaited(operation.whenComplete(() => _deletions.remove(id)));
    return operation;
  }

  Future<void> _cleanupRetired(JobRecord job) async {
    await _cleanup(job.id);
    if (identical(_retired[job.id], job)) _retired.remove(job.id);
  }

  void _releaseReader(JobRecord job) {
    job.readers--;
    if (job.readers == 0 && identical(_retired[job.id], job)) {
      unawaited(_cleanupRetired(job));
    }
  }

  Future<void> _bestEffort(
    Future<void> Function() operation, {
    String? jobId,
  }) async {
    try {
      await operation();
    } catch (error, stack) {
      logFailure(
        _log,
        Level.WARNING,
        'storage.cleanup.failed',
        error,
        stack,
        fields: {'jobId': jobId},
      );
      // Cleanup cannot invalidate a decoded result or stop queue progression.
      try {
        _onCleanupError?.call(error, stack);
      } catch (_) {
        // A diagnostic callback must not interrupt the scheduler either.
      }
    }
  }

  void _track<T>(Future<T> operation, Set<Future<void>> pending) {
    final completion = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    pending.add(completion);
    unawaited(completion.whenComplete(() => pending.remove(completion)));
  }
}

String _safeName(String name) {
  final clean = p.posix
      .basename(name.replaceAll('\\', '/'))
      .replaceAll(RegExp(r'[\x00-\x1f\x7f<>:"|?*]'), '_');
  if (clean.isEmpty || clean.length > 180) {
    throw const ServiceException(ServiceError.invalidFilename);
  }
  return clean;
}

String _randomId() {
  final random = Random.secure();
  return List.generate(
    24,
    (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}
