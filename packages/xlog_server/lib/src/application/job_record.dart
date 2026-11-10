import '../domain/decode_result.dart';
import '../domain/job_snapshot.dart';
import '../domain/job_status.dart';

/// Internal mutable lifecycle record; consumers receive immutable snapshots.
class JobRecord {
  JobRecord(this.id, this.name);

  final String id, name;
  String? workspacePath;
  JobStatus status = JobStatus.uploading;
  DecodeResult? result;
  String? errorCode;
  DateTime? finishedAt;
  int readers = 0;

  JobSnapshot snapshot() => JobSnapshot(
    id: id,
    name: name,
    status: status,
    result: result,
    errorCode: errorCode,
    finishedAt: finishedAt,
  );
}
