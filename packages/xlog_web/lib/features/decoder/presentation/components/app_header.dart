import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

import '../../../../l10n/strings.dart';

class AppHeader extends StatelessComponent {
  const AppHeader({
    super.key,
    required this.strings,
    required this.locale,
    required this.onLanguageChanged,
  });

  final Strings strings;
  final String locale;
  final ValueChanged<String> onLanguageChanged;

  @override
  Component build(BuildContext context) => header(classes: 'topbar', [
    div(classes: 'brand', [
      div(
        classes: 'brand-mark',
        attributes: {'aria-hidden': 'true'},
        [Component.text('>_')],
      ),
      div(classes: 'brand-copy', [
        h1([Component.text(strings.text('title'))]),
        p([Component.text(strings.text('subtitle'))]),
      ]),
    ]),
    div(classes: 'header-actions', [
      select(
        [
          for (final language in Strings.languages.entries)
            option(value: language.key, [Component.text(language.value)]),
        ],
        id: 'language',
        classes: 'language-switch',
        value: locale,
        attributes: {'aria-label': strings.text('language')},
        onChange: (values) {
          if (values.isNotEmpty) onLanguageChanged(values.first);
        },
      ),
      span(classes: 'pill', [Component.text(strings.text('serverProcessing'))]),
    ]),
  ]);
}
