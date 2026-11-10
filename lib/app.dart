import 'package:flutter/material.dart';

import 'features/decoder/data/decoder_preferences.dart';
import 'features/decoder/presentation/decoder_page.dart';
import 'l10n/app_language.dart';
import 'l10n/app_localizations.dart';
import 'theme/app_theme.dart';

class XlogDecoderApp extends StatefulWidget {
  const XlogDecoderApp({super.key, this.home, this.preferences});

  final Widget? home;
  final DecoderPreferencesStore? preferences;

  @override
  State<XlogDecoderApp> createState() => _XlogDecoderAppState();
}

class _XlogDecoderAppState extends State<XlogDecoderApp> {
  final _messenger = GlobalKey<ScaffoldMessengerState>();
  Locale? _locale;
  bool _languageChanged = false;
  Future<void> _pendingSave = Future.value();

  @override
  void initState() {
    super.initState();
    // Keep the initial workspace visible while accessing native storage.
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadLanguage());
  }

  Future<void> _loadLanguage() async {
    try {
      final code = await widget.preferences?.loadLanguageCode();
      if (!mounted || _languageChanged) return;
      final supported = AppLocalizations.supportedLocales;
      setState(() {
        _locale = supported
            .where((locale) => locale.languageCode == code)
            .firstOrNull;
      });
    } catch (_) {
      if (mounted && !_languageChanged) _showLanguageError(saving: false);
    }
  }

  void _showLanguageError({required bool saving}) {
    final context = _messenger.currentContext;
    if (!mounted || context == null) return;
    final l10n = _locale == null
        ? AppLocalizations.of(context)
        : lookupAppLocalizations(_locale!);
    _messenger.currentState?.showSnackBar(
      SnackBar(
        content: Text(saving ? l10n.languageSaveError : l10n.languageLoadError),
      ),
    );
  }

  void _changeLanguage(Locale? locale) {
    _languageChanged = true;
    setState(() => _locale = locale);
    // Serialize quick menu selections so the last choice survives a restart.
    _pendingSave = _pendingSave
        .then((_) async {
          await widget.preferences?.saveLanguageCode(locale?.languageCode);
        })
        .catchError((Object _) {
          if (mounted) _showLanguageError(saving: true);
        });
  }

  @override
  Widget build(BuildContext context) => AppLanguage(
    locale: _locale,
    onChanged: _changeLanguage,
    child: MaterialApp(
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      locale: _locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      scaffoldMessengerKey: _messenger,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: widget.home ?? DecoderPage(preferences: widget.preferences),
    ),
  );
}
