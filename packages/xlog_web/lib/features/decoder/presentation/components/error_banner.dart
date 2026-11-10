import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

import '../../../../l10n/strings.dart';

String errorText(Strings strings, String key) => key.startsWith('error_')
    ? strings.error(key.substring(6))
    : strings.text(key);

class ErrorBanner extends StatelessComponent {
  const ErrorBanner({
    super.key,
    required this.strings,
    required this.errorKey,
    this.onRetry,
  });

  final Strings strings;
  final String errorKey;
  final void Function()? onRetry;

  @override
  Component build(BuildContext context) => div(
    classes: 'error-banner',
    attributes: {'role': 'alert'},
    [
      Component.text(errorText(strings, errorKey)),
      if (onRetry != null)
        button(classes: 'link-button retry-service', onClick: onRetry, [
          Component.text(strings.text('retry')),
        ]),
    ],
  );
}
