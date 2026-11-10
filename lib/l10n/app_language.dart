import 'package:flutter/material.dart';

import 'app_localizations.dart';

/// The null locale follows the platform's preferred languages.
class AppLanguage extends InheritedWidget {
  const AppLanguage({
    super.key,
    required this.locale,
    required this.onChanged,
    required super.child,
  });

  final Locale? locale;
  final ValueChanged<Locale?> onChanged;

  static AppLanguage? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppLanguage>();

  @override
  bool updateShouldNotify(AppLanguage oldWidget) => locale != oldWidget.locale;
}

class LanguageMenu extends StatelessWidget {
  const LanguageMenu({super.key});

  @override
  Widget build(BuildContext context) {
    final language = AppLanguage.maybeOf(context);
    if (language == null) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    return PopupMenuButton<String>(
      key: const Key('language-menu'),
      tooltip: l10n.language,
      initialValue: language.locale?.languageCode ?? 'system',
      onSelected: (code) =>
          language.onChanged(code == 'system' ? null : Locale(code)),
      itemBuilder: (context) => [
        CheckedPopupMenuItem(
          value: 'system',
          checked: language.locale == null,
          child: Text(l10n.systemLanguage),
        ),
        for (final locale in AppLocalizations.supportedLocales)
          CheckedPopupMenuItem(
            value: locale.languageCode,
            checked: language.locale?.languageCode == locale.languageCode,
            child: Text(
              // Endonyms keep the menu usable in any selected language.
              lookupAppLocalizations(locale).languageName,
            ),
          ),
      ],
      icon: const Icon(Icons.language_rounded, size: 21),
    );
  }
}
