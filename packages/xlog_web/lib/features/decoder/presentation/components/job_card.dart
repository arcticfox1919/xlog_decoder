import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

import '../../../../l10n/strings.dart';
import '../../domain/models.dart';
import '../formatters.dart';
import 'error_banner.dart';

class JobCard extends StatelessComponent {
  const JobCard({
    super.key,
    required this.strings,
    required this.job,
    required this.onCancel,
  });

  final Strings strings;
  final JobEntry job;
  final VoidCallback onCancel;

  @override
  Component build(BuildContext context) => article(classes: 'job-card', [
    div(classes: 'job-topline', [
      h3(classes: 'job-name', [Component.text(job.name)]),
      span(
        classes: 'status-badge',
        attributes: {'data-status': job.status},
        [Component.text(strings.status(job.status))],
      ),
    ]),
    if (job.status == 'uploading')
      div(
        classes: 'progress-track',
        attributes: {
          'role': 'progressbar',
          'aria-valuemin': '0',
          'aria-valuemax': '100',
          'aria-valuenow': '${(job.progress * 100).round()}',
          'aria-label': strings.text('uploading'),
        },
        [
          div(
            classes: 'progress-fill',
            attributes: {'style': 'width:${(job.progress * 100).round()}%'},
            [],
          ),
        ],
      ),
    if (job.result != null && job.finished && job.status != 'failure')
      p(classes: 'job-meta', [
        Component.text(
          '${job.result!.blockCount} ${strings.text('blocks')} · ${formatBytes(job.result!.outputBytes)}${job.result!.issueCount > 0 ? ' · ${job.result!.issueCount} ${strings.text('notes')}' : ''}',
        ),
      ]),
    if (job.errorKey != null)
      p(
        classes: 'job-error',
        attributes: {'role': 'alert'},
        [Component.text(errorText(strings, job.errorKey!))],
      ),
    if (job.download != null || job.status == 'queued')
      div(classes: 'job-actions', [
        if (job.download != null)
          a(
            href: job.download!,
            classes: 'primary-button',
            attributes: {'download': '', 'referrerpolicy': 'no-referrer'},
            [Component.text(strings.text('download'))],
          ),
        if (job.status == 'queued')
          button(classes: 'link-button', onClick: onCancel, [
            Component.text(strings.text('cancel')),
          ]),
      ]),
  ]);
}
