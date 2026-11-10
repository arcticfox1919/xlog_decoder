import 'dart:async';

import '../domain/decoder_api.dart';
import '../domain/models.dart';
import 'decoder_state.dart';

/// Owns service initialization, upload batches and job polling independently of the UI.
class DecoderController {
  DecoderController({
    required Uri baseUri,
    required DecoderApiFactory createApi,
    Duration pollInterval = const Duration(seconds: 1),
  }) : _baseUri = _serviceBase(baseUri),
       _createApi = createApi,
       _pollInterval = pollInterval;

  static const historyLimit = 50;

  final Uri _baseUri;
  final DecoderApiFactory _createApi;
  final Duration _pollInterval;
  final _changes = StreamController<DecoderState>.broadcast();
  final _cancelling = <int>{};
  DecoderState _state = DecoderState();
  DecoderApi? _api;
  DecoderApi? _initializingApi;
  Timer? _timer;
  bool _polling = false;
  bool _disposed = false;
  String? _pollErrorKey;
  int _nextLocalId = 0;

  DecoderState get state => _state;
  Stream<DecoderState> get changes => _changes.stream;

  void _emit(DecoderState state) {
    if (_disposed) return;
    _state = state;
    _changes.add(state);
  }

  Future<void> initialize() async {
    if (_disposed || _state.initializing || _state.busy) return;
    _pollErrorKey = null;
    _emit(
      _state.copyWith(initializing: true, ready: false, errorKey: () => null),
    );
    DecoderApi? api;
    try {
      api = _createApi(_baseUri);
      _initializingApi = api;
      final limit = await api.health();
      if (_disposed) return;
      final previous = _api;
      _api = api;
      _initializingApi = null;
      if (!identical(previous, api)) previous?.close();
      _emit(_state.copyWith(maxUploadBytes: limit, ready: true));
    } catch (error) {
      _emit(_state.copyWith(errorKey: () => _errorKey(error)));
    } finally {
      if (api != null && identical(_initializingApi, api)) {
        _initializingApi = null;
        api.close();
      }
      _emit(_state.copyWith(initializing: false));
    }
  }

  Future<void> upload(List<UploadFile> files) async {
    if (_disposed || _state.uploading || files.isEmpty) return;
    final api = _api;
    if (!_state.ready || api == null) {
      _emit(_state.copyWith(errorKey: () => 'serviceUnavailable'));
      return;
    }
    // Capture the batch so callers cannot alter an upload in progress.
    final batch = List<UploadFile>.of(files);
    _pollErrorKey = null;
    _emit(_state.copyWith(uploading: true, errorKey: () => null));
    try {
      for (final file in batch) {
        if (_disposed) return;
        if (_state.jobs.length >= historyLimit) {
          _emit(_state.copyWith(errorKey: () => 'historyFull'));
          break;
        }
        final entry = JobEntry(localId: _nextLocalId++, name: file.name);
        _emit(_state.copyWith(jobs: [entry, ..._state.jobs]));
        if (file.size > _state.maxUploadBytes) {
          _updateEntry(entry.localId, (job) => job.withFailure('fileTooLarge'));
          continue;
        }
        try {
          final result = await api.upload(
            file,
            onProgress: (value) {
              _updateEntry(
                entry.localId,
                (job) => job.status == 'uploading'
                    ? job.withProgress(value.clamp(0, 1))
                    : job,
              );
            },
          );
          if (_disposed) return;
          _updateEntry(
            entry.localId,
            (job) => job.withResult(result, download: api.downloadLink(result)),
          );
          _schedulePoll();
        } catch (error) {
          _updateEntry(
            entry.localId,
            (job) => job.withFailure(_errorKey(error)),
          );
        }
      }
    } finally {
      _emit(_state.copyWith(uploading: false));
      _schedulePoll();
    }
  }

  void _updateEntry(int localId, JobEntry Function(JobEntry) update) {
    if (_disposed) return;
    final index = _state.jobs.indexWhere((job) => job.localId == localId);
    if (index < 0) return;
    final current = _state.jobs[index];
    final next = update(current);
    if (identical(current, next)) return;
    final jobs = List<JobEntry>.of(_state.jobs)..[index] = next;
    _emit(_state.copyWith(jobs: jobs));
  }

  bool get _hasPendingJobs =>
      _state.jobs.any((job) => job.id != null && !job.finished);

  void _schedulePoll() {
    if (_disposed || _timer?.isActive == true || _polling || !_hasPendingJobs) {
      return;
    }
    _timer = Timer(_pollInterval, () {
      _timer = null;
      unawaited(_poll());
    });
  }

  Future<void> _poll() async {
    final api = _api;
    if (_disposed || _polling || api == null) return;
    _polling = true;
    var failed = false;
    try {
      final pending = _state.jobs
          .where((job) => job.id != null && !job.finished)
          .toList();
      for (final entry in pending) {
        if (_disposed) return;
        // A cancellation can finish while an earlier request is awaiting I/O.
        if (_state.jobs.any(
          (job) => job.localId == entry.localId && job.finished,
        )) {
          continue;
        }
        try {
          final result = await api.job(entry.id!);
          if (_disposed) return;
          _updateEntry(
            entry.localId,
            (job) => job.finished
                ? job
                : job.withResult(result, download: api.downloadLink(result)),
          );
        } catch (error) {
          if (_disposed) return;
          if (_state.jobs.any(
            (job) => job.localId == entry.localId && job.finished,
          )) {
            continue;
          }
          if (error is ApiException &&
              const {'not_found', 'forbidden'}.contains(error.code)) {
            _updateEntry(
              entry.localId,
              (job) => job.finished ? job : job.withFailure(_errorKey(error)),
            );
          } else {
            failed = true;
            _pollErrorKey = _errorKey(error);
            _emit(_state.copyWith(errorKey: () => _pollErrorKey));
          }
        }
      }
      if (!failed && _pollErrorKey != null) {
        final recoveredError = _pollErrorKey;
        _pollErrorKey = null;
        if (_state.errorKey == recoveredError) {
          _emit(_state.copyWith(errorKey: () => null));
        }
      }
    } finally {
      _polling = false;
      _schedulePoll();
    }
  }

  Future<void> cancel(JobEntry entry) async {
    final api = _api;
    if (_disposed || api == null || _cancelling.contains(entry.localId)) return;
    final current = _state.jobs
        .where((job) => job.localId == entry.localId)
        .firstOrNull;
    if (current == null || current.id == null || current.status != 'queued') {
      return;
    }
    _cancelling.add(entry.localId);
    try {
      await api.cancel(current.id!);
      _updateEntry(
        current.localId,
        (job) => job.finished ? job : job.cancelled(),
      );
      if (!_hasPendingJobs) {
        _timer?.cancel();
        _timer = null;
      }
    } catch (error) {
      _emit(_state.copyWith(errorKey: () => _errorKey(error)));
    } finally {
      _cancelling.remove(entry.localId);
    }
  }

  void clearHistory() {
    if (_disposed || _state.busy) return;
    _emit(_state.copyWith(jobs: []));
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    final api = _api;
    final initializingApi = _initializingApi;
    _api = null;
    _initializingApi = null;
    api?.close();
    if (!identical(api, initializingApi)) initializingApi?.close();
    unawaited(_changes.close());
  }

  static String _errorKey(Object error) =>
      error is ApiException ? 'error_${error.code}' : 'error_unknown';
}

Uri _serviceBase(Uri uri) {
  if (!const {'http', 'https'}.contains(uri.scheme) ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment) {
    throw ArgumentError.value(
      uri,
      'baseUri',
      'Expected an HTTP(S) service URL',
    );
  }
  return uri.replace(path: uri.path.endsWith('/') ? uri.path : '${uri.path}/');
}
