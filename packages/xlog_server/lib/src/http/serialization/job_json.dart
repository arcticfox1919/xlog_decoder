import '../../domain/job_snapshot.dart';

Map<String, Object?> jobJson(JobSnapshot job) => {
  'id': job.id,
  'name': job.name,
  'status': job.status.name,
  if (job.result case final result?) ...{
    'outputBytes': result.outputBytes,
    'blockCount': result.blockCount,
    'issueCount': result.issueCount,
    'downloadUrl': '/api/jobs/${job.id}/download',
  },
  if (job.errorCode != null)
    'error': {
      'code': job.errorCode,
      'message':
          'No result could be decoded. Check the file format and server key configuration.',
    },
};
