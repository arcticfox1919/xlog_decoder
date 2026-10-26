import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xlog_decoder/app.dart';
import 'package:xlog_decoder/features/decoder/application/decoder_controller.dart';
import 'package:xlog_decoder/features/decoder/data/file_dialog_service.dart';
import 'package:xlog_decoder/features/decoder/presentation/decoder_page.dart';

import 'support/fake_log_file_service.dart';

class FakeDialogs implements FileDialogService {
  List<String> paths = ['picked.xlog'];
  @override
  Future<List<String>> selectLogs() async => paths;
  @override
  Future<String?> selectDirectory() async => 'chosen-output';
  @override
  Future<String?> readPrivateKey() async => '0' * 63 + '1';
}

void main() {
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
  );

  testWidgets('Dropping a ZIP automatically uses the same decode flow', (
    tester,
  ) async {
    final service = FakeLogFileService();
    final controller = DecoderController(service: service);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      XlogDecoderApp(
        home: DecoderPage(controller: controller, dialogs: FakeDialogs()),
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
    expect(tester.takeException(), isNull);
  });

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
