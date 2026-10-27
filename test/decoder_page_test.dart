import 'dart:async';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xlog_decoder/app.dart';
import 'package:xlog_decoder/features/decoder/application/decoder_controller.dart';
import 'package:xlog_decoder/features/decoder/data/file_dialog_service.dart';
import 'package:xlog_decoder/features/decoder/presentation/decoder_page.dart';

import 'support/fake_log_file_service.dart';
import 'support/fake_preferences_store.dart';
import 'package:xlog_decoder/features/decoder/data/decoder_preferences.dart';
import 'package:xlog_decoder/features/decoder/presentation/widgets/decoder_settings.dart';

class FakeDialogs implements FileDialogService {
  List<String> paths = ['picked.xlog'];
  String? directory = 'chosen-output';
  int directorySelections = 0;
  @override
  Future<List<String>> selectLogs() async => paths;
  @override
  Future<String?> selectDirectory() async {
    directorySelections++;
    return directory;
  }

  @override
  Future<String?> readPrivateKey() async => '0' * 63 + '1';
}

class DelayedPreferencesStore extends FakePreferencesStore {
  final pending = Completer<DecoderPreferences>();

  @override
  Future<DecoderPreferences> load() => pending.future;
}

void main() {
  testWidgets(
    'Workspace renders while settings load, then restores and enables decoding',
    (tester) async {
      final preferences = DelayedPreferencesStore();
      final service = FakeLogFileService();
      final controller = DecoderController(service: service);
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        XlogDecoderApp(
          home: DecoderPage(
            controller: controller,
            dialogs: FakeDialogs(),
            preferences: preferences,
          ),
        ),
      );
      expect(find.text('Xlog 解码器'), findsOneWidget);
      expect(find.text('添加日志'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('select-files')))
            .onPressed,
        isNull,
      );
      expect(
        tester.widget<DropTarget>(find.byType(DropTarget)).enable,
        isFalse,
      );
      expect(service.requests, isEmpty);

      final key = '0' * 63 + '1';
      preferences.pending.complete(
        DecoderPreferences(outputDirectory: 'saved-output', privateKeyHex: key),
      );
      await tester.pumpAndSettle();
      expect(find.text('saved-output'), findsOneWidget);
      expect(tester.widget<DropTarget>(find.byType(DropTarget)).enable, isTrue);
      await tester.tap(find.byKey(const Key('select-files')));
      await tester.pumpAndSettle();
      expect(service.requests.single.outputDirectory, 'saved-output');
      expect(service.requests.single.privateKeyHex, key);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Directory row and private key restore after reopening the page',
    (tester) async {
      final preferences = FakePreferencesStore();
      await tester.pumpWidget(
        XlogDecoderApp(
          home: DecoderPage(dialogs: FakeDialogs(), preferences: preferences),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('选择目录'), findsNothing);
      await tester.tap(find.byKey(const Key('choose-output-directory')));
      await tester.pumpAndSettle();
      expect(preferences.directory, 'chosen-output');
      final key = '0' * 63 + '1';
      await tester.enterText(find.byKey(const Key('private-key')), key);
      await tester.pumpAndSettle();
      expect(preferences.privateKey, key);

      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        XlogDecoderApp(
          home: DecoderPage(dialogs: FakeDialogs(), preferences: preferences),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('chosen-output'), findsOneWidget);
      final field = tester.widget<TextField>(
        find.byKey(const Key('private-key')),
      );
      expect(field.controller!.text, key);
      expect(field.obscureText, isTrue);
      await tester.tap(find.text('恢复默认'));
      await tester.pumpAndSettle();
      expect(preferences.directory, isNull);
      await tester.enterText(find.byKey(const Key('private-key')), '');
      await tester.pumpAndSettle();
      expect(preferences.privateKey, isEmpty);
    },
  );

  testWidgets('720px desktop keeps compact cards side by side', (tester) async {
    await tester.binding.setSurfaceSize(const Size(720, 850));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const XlogDecoderApp());
    final drop = tester.getRect(find.byKey(const Key('log-drop-zone')));
    final settings = tester.getRect(find.byType(DecoderSettings));
    expect(drop.top, settings.top);
    expect(drop.right, lessThan(settings.left));
    expect(drop.width, lessThan(400));
    expect(drop.height, lessThan(400));
    expect(find.text('Xlog 解码器'), findsOneWidget);
    expect(find.text('让日志重新可读'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'File button automatically starts decoding with selected directory',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final service = FakeLogFileService();
      final controller = DecoderController(service: service);
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        XlogDecoderApp(
          home: DecoderPage(controller: controller, dialogs: FakeDialogs()),
        ),
      );
      await tester.tap(find.byKey(const Key('choose-output-directory')));
      await tester.pumpAndSettle();
      expect(find.text('chosen-output'), findsOneWidget);
      await tester.tap(find.text('从文件导入私钥'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('select-files')));
      await tester.pumpAndSettle();
      expect(service.requests.single.inputPath, 'picked.xlog');
      expect(service.requests.single.outputDirectory, 'chosen-output');
      expect(service.requests.single.privateKeyHex, '0' * 63 + '1');
      expect(find.text('已完成'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant({
      TargetPlatform.windows,
      TargetPlatform.macOS,
    }),
  );

  testWidgets(
    'Dropping a ZIP automatically uses the same decode flow',
    (tester) async {
      final service = FakeLogFileService();
      final controller = DecoderController(service: service);
      addTearDown(controller.dispose);
      final dialogs = FakeDialogs();
      await tester.pumpWidget(
        XlogDecoderApp(
          home: DecoderPage(controller: controller, dialogs: dialogs),
        ),
      );
      final target = tester.widget<DropTarget>(find.byType(DropTarget));
      target.onDragDone!(
        DropDoneDetails(
          files: [DropItemFile('dropped.zip')],
          localPosition: Offset.zero,
          globalPosition: Offset.zero,
        ),
      );
      await tester.pumpAndSettle();
      expect(service.requests.single.inputPath, 'dropped.zip');
      expect(service.requests.single.outputDirectory, isNull);
      expect(dialogs.directorySelections, 0);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant({
      TargetPlatform.windows,
      TargetPlatform.macOS,
    }),
  );

  testWidgets('Compact layout fits a narrow desktop window', (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 850));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const XlogDecoderApp());
    expect(find.byKey(const Key('select-files')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Cancelled selection does not start a task', (tester) async {
    final service = FakeLogFileService();
    final controller = DecoderController(service: service);
    addTearDown(controller.dispose);
    final dialogs = FakeDialogs()..paths = [];
    await tester.pumpWidget(
      XlogDecoderApp(
        home: DecoderPage(controller: controller, dialogs: dialogs),
      ),
    );
    await tester.tap(find.byKey(const Key('select-files')));
    await tester.pumpAndSettle();
    expect(service.requests, isEmpty);
  });
}
