import 'dart:async';

import 'package:jaspr/jaspr.dart';

import 'browser/browser_environment.dart';
import 'features/decoder/application/decoder_controller.dart';
import 'features/decoder/application/decoder_state.dart';
import 'features/decoder/data/backend_api.dart';
import 'features/decoder/domain/decoder_api.dart';
import 'features/decoder/presentation/decoder_page.dart';
import 'l10n/strings.dart';

/// Composes browser adapters, application state, and the decoder page.
class App extends StatefulComponent {
  const App({super.key, this.createApi});

  final DecoderApiFactory? createApi;

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> {
  final _environment = BrowserEnvironment();
  late final DecoderController _controller;
  late final StreamSubscription<DecoderState> _subscription;
  late String _locale;

  @override
  void initState() {
    super.initState();
    _locale = _environment.initialLocale();
    _environment.updateDocument(_locale);
    _controller = DecoderController(
      baseUri: _environment.initialServiceAddress(),
      createApi: (uri) => component.createApi?.call(uri) ?? BackendApi(uri),
    );
    _subscription = _controller.changes.listen((_) {
      if (mounted) setState(() {});
    });
    scheduleMicrotask(_controller.initialize);
  }

  @override
  void dispose() {
    unawaited(_subscription.cancel());
    _controller.dispose();
    super.dispose();
  }

  void _changeLanguage(String locale) {
    if (!Strings.languages.containsKey(locale)) return;
    setState(() => _locale = locale);
    _environment.saveLocale(locale);
    _environment.updateDocument(locale);
  }

  @override
  Component build(BuildContext context) => DecoderPage(
    state: _controller.state,
    strings: Strings(_locale),
    locale: _locale,
    onLanguageChanged: _changeLanguage,
    onRetry: _controller.initialize,
    onFiles: _controller.upload,
    onCancel: _controller.cancel,
    onClear: _controller.clearHistory,
  );
}
