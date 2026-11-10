import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

import '../../../../l10n/strings.dart';
import '../../domain/models.dart';
import 'job_card.dart';

class HistoryPanel extends StatelessComponent {
  const HistoryPanel({
    super.key,
    required this.strings,
    required this.jobs,
    required this.busy,
    required this.onClear,
    required this.onCancel,
  });

  final Strings strings;
  final List<JobEntry> jobs;
  final bool busy;
  final VoidCallback onClear;
  final ValueChanged<JobEntry> onCancel;

  @override
  Component build(BuildContext context) => section(classes: 'history-section', [
    div(classes: 'history-heading', [
      h2([Component.text(strings.text('history'))]),
      button(
        classes: 'link-button',
        disabled: busy || jobs.isEmpty,
        onClick: onClear,
        [Component.text(strings.text('clear'))],
      ),
    ]),
    if (jobs.isEmpty)
      div(classes: 'panel empty-state', [
        div(attributes: {'aria-hidden': 'true'}, [Component.text('⌁')]),
        h3([Component.text(strings.text('empty'))]),
        p([Component.text(strings.text('emptyHint'))]),
      ])
    else
      div(classes: 'history-list', [
        for (final job in jobs)
          JobCard(
            key: ValueKey(job.localId),
            strings: strings,
            job: job,
            onCancel: () => onCancel(job),
          ),
      ]),
  ]);
}
