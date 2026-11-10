import '../domain/models.dart';

/// A snapshot safe to retain while later controller operations run.
class DecoderState {
  DecoderState({
    List<JobEntry> jobs = const [],
    this.ready = false,
    this.initializing = false,
    this.uploading = false,
    this.maxUploadBytes = 256 * 1024 * 1024,
    this.errorKey,
  }) : jobs = List.unmodifiable(jobs);

  final List<JobEntry> jobs;
  final bool ready;
  final bool initializing;
  final bool uploading;
  final int maxUploadBytes;
  final String? errorKey;

  bool get busy => uploading || jobs.any((job) => !job.finished);

  DecoderState copyWith({
    List<JobEntry>? jobs,
    bool? ready,
    bool? initializing,
    bool? uploading,
    int? maxUploadBytes,
    String? Function()? errorKey,
  }) => DecoderState(
    jobs: jobs ?? this.jobs,
    ready: ready ?? this.ready,
    initializing: initializing ?? this.initializing,
    uploading: uploading ?? this.uploading,
    maxUploadBytes: maxUploadBytes ?? this.maxUploadBytes,
    errorKey: errorKey == null ? this.errorKey : errorKey(),
  );
}
