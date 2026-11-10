import 'decode_result.dart';
import 'job_status.dart';

class JobSnapshot {
  const JobSnapshot({
    required this.id,
    required this.name,
    required this.status,
    this.result,
    this.errorCode,
    this.finishedAt,
  });

  final String id;
  final String name;
  final JobStatus status;
  final DecodeResult? result;
  final String? errorCode;
  final DateTime? finishedAt;
}
