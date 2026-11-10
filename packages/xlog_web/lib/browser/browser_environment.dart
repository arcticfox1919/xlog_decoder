import 'package:web/web.dart' as web;

import '../l10n/strings.dart';

/// Browser-only preferences, location, and document metadata.
///
/// Only the interface language is persisted.
class BrowserEnvironment {
  String initialLocale() {
    String? saved;
    try {
      saved = web.window.localStorage.getItem('xlog.language');
    } catch (_) {
      // Storage can be unavailable in privacy-restricted browser contexts.
    }
    if (Strings.languages.containsKey(saved)) return saved!;
    return web.window.navigator.language.startsWith('zh') ? 'zh' : 'en';
  }

  Uri initialServiceAddress() {
    const configured = String.fromEnvironment('XLOG_API_BASE_URL');
    return Uri.parse(
      configured.isNotEmpty ? configured : '${Uri.base.origin}/',
    );
  }

  void saveLocale(String locale) {
    try {
      web.window.localStorage.setItem('xlog.language', locale);
    } catch (_) {
      // The current page still switches language when storage is unavailable.
    }
  }

  void updateDocument(String locale) {
    web.document.title = Strings(locale).text('title');
    web.document.documentElement?.setAttribute(
      'lang',
      locale == 'zh' ? 'zh-CN' : 'en',
    );
  }
}
