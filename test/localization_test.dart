import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xlog_decoder/app.dart';
import 'package:xlog_decoder/features/decoder/application/decoder_controller.dart';
import 'package:xlog_decoder/features/decoder/domain/decode_failure.dart';
import 'package:xlog_decoder/features/decoder/domain/decode_models.dart';
import 'package:xlog_decoder/features/decoder/presentation/decoder_page.dart';
import 'package:xlog_decoder/l10n/app_localizations.dart';

import 'support/fake_log_file_service.dart';
import 'support/fake_preferences_store.dart';

class DelayedLanguageStore extends FakePreferencesStore {
  final language = Completer<String?>();

  @override
  Future<String?> loadLanguageCode() => language.future;
}

class FailingLanguageStore extends FakePreferencesStore {
  @override
  Future<void> saveLanguageCode(String? value) async =>
      throw StateError('disk');
}

Future<void> selectLanguage(WidgetTester tester, String name) async {
  await tester.tap(find.byKey(const Key('language-menu')));
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(CheckedPopupMenuItem<String>, name));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    final dispatcher =
        TestWidgetsFlutterBinding.ensureInitialized().platformDispatcher;
    dispatcher.localesTestValue = const [Locale('zh', 'CN')];
    addTearDown(dispatcher.clearLocalesTestValue);
  });

  testWidgets(
    'Switches immediately, preserves input, and restores the language',
    (tester) async {
      final preferences = FakePreferencesStore();
      await tester.pumpWidget(XlogDecoderApp(preferences: preferences));
      await tester.pumpAndSettle();
      expect(find.text('Xlog 解码器'), findsOneWidget);
      final key = '0' * 63 + '1';
      await tester.enterText(find.byKey(const Key('private-key')), key);
      await selectLanguage(tester, 'English');
      expect(find.text('Xlog Decoder'), findsOneWidget);
      expect(find.text('Select files'), findsOneWidget);
      expect(preferences.languageCode, 'en');
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('private-key')))
            .controller!
            .text,
        key,
      );

      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(XlogDecoderApp(preferences: preferences));
      await tester.pumpAndSettle();
      expect(find.text('Xlog Decoder'), findsOneWidget);
      await selectLanguage(tester, '简体中文');
      expect(find.text('选择文件'), findsOneWidget);
      await selectLanguage(tester, '跟随系统');
      expect(preferences.languageCode, isNull);
      tester.binding.platformDispatcher.localesTestValue = const [Locale('en')];
      await tester.pumpAndSettle();
      expect(find.text('Select files'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Uses English for an unsupported system or stored language', (
    tester,
  ) async {
    tester.binding.platformDispatcher.localesTestValue = const [Locale('fr')];
    final preferences = FakePreferencesStore()..languageCode = 'unknown';
    await tester.pumpWidget(XlogDecoderApp(preferences: preferences));
    await tester.pumpAndSettle();
    expect(find.text('Xlog Decoder'), findsOneWidget);
  });

  testWidgets('A late preference read cannot undo a user selection', (
    tester,
  ) async {
    final preferences = DelayedLanguageStore();
    await tester.pumpWidget(XlogDecoderApp(preferences: preferences));
    await tester.pumpAndSettle();
    await selectLanguage(tester, 'English');
    preferences.language.complete('zh');
    await tester.pumpAndSettle();
    expect(find.text('Xlog Decoder'), findsOneWidget);
    expect(preferences.languageCode, 'en');
  });

  testWidgets('Save failures show a localized message', (tester) async {
    await tester.pumpWidget(
      XlogDecoderApp(preferences: FailingLanguageStore()),
    );
    await tester.pumpAndSettle();
    await selectLanguage(tester, 'English');
    expect(
      find.text('Could not save the language setting. Please try again.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Existing errors and validation follow the selected language', (
    tester,
  ) async {
    final controller = DecoderController(
      service: FakeLogFileService(
        handler: (_) async =>
            throw const DecodeFailure(DecodeErrorCode.inputMissing),
      ),
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      XlogDecoderApp(home: DecoderPage(controller: controller)),
    );
    await controller.decodePaths(['missing.xlog']);
    await tester.pumpAndSettle();
    expect(find.text('找不到输入文件，请重新选择。'), findsOneWidget);
    await selectLanguage(tester, 'English');
    expect(find.text('Input file not found. Select it again.'), findsOneWidget);
    await controller.decodePaths(['key.xlog'], privateKeyHex: 'invalid');
    await tester.pumpAndSettle();
    expect(
      find.text(lookupAppLocalizations(const Locale('en')).invalidPrivateKey),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('English fits a narrow window', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 850));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = DecoderController(
      service: FakeLogFileService(
        handler: (_) async => DecodeBatchResult([
          const DecodedFile(
            sourceName: 'app.xlog',
            outputPath: 'app.log',
            issues: ['Technical diagnostic'],
          ),
        ]),
      ),
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      XlogDecoderApp(home: DecoderPage(controller: controller)),
    );
    await selectLanguage(tester, 'English');
    await controller.decodePaths(['app.xlog']);
    await tester.pumpAndSettle();
    expect(find.text('Partially recovered'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('English messages handle singular and plural counts', () {
    final l10n = lookupAppLocalizations(const Locale('en'));
    expect(l10n.taskCount(1), '1 task');
    expect(l10n.taskCount(2), '2 tasks');
    expect(l10n.generatedLogs(0), 'Generated 0 logs');
    expect(l10n.logBlocks(1), '1 log block');
    expect(l10n.logBlocks(3), '3 log blocks');
  });
}
