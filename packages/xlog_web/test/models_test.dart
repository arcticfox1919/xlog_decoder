import 'package:test/test.dart';
import 'package:xlog_web/features/decoder/domain/models.dart';
import 'package:xlog_web/l10n/strings.dart';

void main() {
  test('Polling continues until a result or terminal failure arrives', () {
    for (final status in ['queued', 'running']) {
      expect(
        RemoteJob(id: 'job', name: 'app.xlog', status: status).finished,
        isFalse,
      );
    }
    for (final status in ['success', 'warning', 'failure', 'cancelled']) {
      expect(
        RemoteJob(id: 'job', name: 'app.xlog', status: status).finished,
        isTrue,
      );
    }
  });

  test('Service results retain download links and structured errors', () {
    final job = RemoteJob.fromJson({
      'id': 'job',
      'name': 'app.xlog',
      'status': 'failure',
      'error': {'code': 'invalid_input', 'message': 'Internal diagnostic'},
    });
    expect(job.errorCode, 'invalid_input');
    expect(job.downloadUrl, isNull);
    expect(job.finished, isTrue);
  });

  test('Unknown service errors show localized text instead of internals', () {
    expect(const Strings('zh').error('internal_diagnostic'), '操作失败，请稍后重试。');
    expect(
      const Strings('en').error('internal_diagnostic'),
      'The operation failed. Please try again.',
    );
    expect(const Strings('fr').text('title'), 'Xlog Decoder');
  });
}
