class RemoteJob {
  const RemoteJob({
    required this.id,
    required this.name,
    required this.status,
    this.outputBytes = 0,
    this.blockCount = 0,
    this.issueCount = 0,
    this.downloadUrl,
    this.errorCode,
  });

  final String id;
  final String name;
  final String status;
  final int outputBytes;
  final int blockCount;
  final int issueCount;
  final String? downloadUrl;
  final String? errorCode;

  bool get finished =>
      const {'success', 'warning', 'failure', 'cancelled'}.contains(status);

  factory RemoteJob.fromJson(Map<String, dynamic> json) => RemoteJob(
    id: json['id'] as String,
    name: json['name'] as String,
    status: json['status'] as String,
    outputBytes: (json['outputBytes'] as num?)?.toInt() ?? 0,
    blockCount: (json['blockCount'] as num?)?.toInt() ?? 0,
    issueCount: (json['issueCount'] as num?)?.toInt() ?? 0,
    downloadUrl: json['downloadUrl'] as String?,
    errorCode: (json['error'] as Map<String, dynamic>?)?['code'] as String?,
  );
}

class ApiException implements Exception {
  const ApiException(this.code, {this.statusCode = 0});
  final String code;
  final int statusCode;
}

/// An immutable upload/history item. The local ID survives remote job updates.
class JobEntry {
  const JobEntry({
    required this.localId,
    required this.name,
    this.id,
    this.status = 'uploading',
    this.progress = 0,
    this.errorKey,
    this.download,
    this.result,
  });

  final int localId;
  final String name;
  final String? id;
  final String status;
  final double progress;
  final String? errorKey;
  final String? download;
  final RemoteJob? result;

  bool get finished =>
      const {'success', 'warning', 'failure', 'cancelled'}.contains(status);

  JobEntry withProgress(double value) => JobEntry(
    localId: localId,
    name: name,
    id: id,
    status: status,
    progress: value,
    errorKey: errorKey,
    download: download,
    result: result,
  );

  JobEntry withResult(RemoteJob job, {required String? download}) => JobEntry(
    localId: localId,
    name: name,
    id: job.id,
    status: job.status,
    progress: progress,
    errorKey: job.errorCode == null ? null : 'error_${job.errorCode}',
    download: download,
    result: job,
  );

  JobEntry withFailure(String errorKey) => JobEntry(
    localId: localId,
    name: name,
    id: id,
    status: 'failure',
    progress: progress,
    errorKey: errorKey,
    result: result,
  );

  JobEntry cancelled() => JobEntry(
    localId: localId,
    name: name,
    id: id,
    status: 'cancelled',
    progress: progress,
    result: result,
  );
}
