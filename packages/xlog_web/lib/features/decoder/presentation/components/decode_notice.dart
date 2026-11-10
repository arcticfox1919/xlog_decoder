import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

import '../../../../l10n/strings.dart';
import '../formatters.dart';

class DecodeNotice extends StatelessComponent {
  const DecodeNotice({
    super.key,
    required this.strings,
    required this.ready,
    required this.initializing,
    required this.maxUploadBytes,
  });

  final Strings strings;
  final bool ready, initializing;
  final int maxUploadBytes;

  @override
  Component build(BuildContext context) =>
      aside(classes: 'panel decode-notice', [
        div(classes: 'panel-heading', [
          h2([Component.text(strings.text('decodeNotice'))]),
        ]),
        p([Component.text(strings.text('automaticDecryption'))]),
        if (initializing)
          p(
            classes: 'helper',
            attributes: {'role': 'status'},
            [Component.text(strings.text('preparing'))],
          ),
        if (ready)
          p(classes: 'upload-limit', [
            Component.text(
              '${strings.text('limits')} · ${formatBytes(maxUploadBytes)}',
            ),
          ]),
      ]);
}
