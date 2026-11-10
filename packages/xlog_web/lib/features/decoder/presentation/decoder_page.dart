import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

import '../../../l10n/strings.dart';
import '../application/decoder_state.dart';
import '../domain/decoder_api.dart';
import '../domain/models.dart';
import 'components/app_header.dart';
import 'components/decode_notice.dart';
import 'components/error_banner.dart';
import 'components/history_panel.dart';
import 'components/upload_panel.dart';

/// Page layout and component wiring; requests and timers belong to the controller.
class DecoderPage extends StatelessComponent {
  const DecoderPage({
    super.key,
    required this.state,
    required this.strings,
    required this.locale,
    required this.onLanguageChanged,
    required this.onRetry,
    required this.onFiles,
    required this.onCancel,
    required this.onClear,
  });

  final DecoderState state;
  final Strings strings;
  final String locale;
  final void Function(String) onLanguageChanged;
  final void Function() onRetry;
  final void Function(List<UploadFile>) onFiles;
  final void Function(JobEntry) onCancel;
  final void Function() onClear;

  @override
  Component build(BuildContext context) => div(classes: 'app-shell', [
    AppHeader(
      strings: strings,
      locale: locale,
      onLanguageChanged: onLanguageChanged,
    ),
    if (state.errorKey != null)
      ErrorBanner(
        strings: strings,
        errorKey: state.errorKey!,
        onRetry: !state.ready && !state.initializing ? onRetry : null,
      ),
    main_([
      div(classes: 'workspace', [
        UploadPanel(
          strings: strings,
          enabled: state.ready,
          uploading: state.uploading,
          onFiles: onFiles,
        ),
        DecodeNotice(
          strings: strings,
          ready: state.ready,
          initializing: state.initializing,
          maxUploadBytes: state.maxUploadBytes,
        ),
      ]),
      HistoryPanel(
        strings: strings,
        jobs: state.jobs,
        busy: state.busy,
        onClear: onClear,
        onCancel: onCancel,
      ),
    ]),
    p(classes: 'privacy-note', [Component.text(strings.text('privacy'))]),
  ]);
}
