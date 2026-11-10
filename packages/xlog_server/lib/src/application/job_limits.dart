class JobLimits {
  JobLimits({
    this.maxUploadBytes = 256 * 1024 * 1024,
    this.maxOutputBytes = 128 * 1024 * 1024,
    this.maxConcurrentJobs = 2,
    this.maxQueuedJobs = 4,
    this.maxRetainedJobs = 64,
    this.jobTtl = const Duration(hours: 1),
    this.uploadTimeout = const Duration(minutes: 10),
  }) {
    if (maxUploadBytes < 1 ||
        maxOutputBytes < 1 ||
        maxConcurrentJobs < 1 ||
        maxQueuedJobs < 0 ||
        maxRetainedJobs < maxConcurrentJobs + maxQueuedJobs ||
        jobTtl <= Duration.zero ||
        uploadTimeout <= Duration.zero) {
      throw ArgumentError('Invalid server resource limits');
    }
  }

  final int maxUploadBytes, maxOutputBytes;
  final int maxConcurrentJobs, maxQueuedJobs, maxRetainedJobs;
  final Duration jobTtl, uploadTimeout;
}
