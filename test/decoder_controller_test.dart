import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:xlog_decoder/features/decoder/application/decoder_controller.dart';
import 'package:xlog_decoder/features/decoder/domain/decode_models.dart';

import 'support/fake_log_file_service.dart';

void main() {
  test('Processes selections in order and keeps results per input', () async {
    final service = FakeLogFileService();
    final controller = DecoderController(service: service);
    addTearDown(controller.dispose);
    controller.setOutputDirectory('chosen');
    await controller.decodePaths(['a.xlog', 'b.zip', 'a.xlog']);
    expect(service.requests.map((request) => request.inputPath), [
      'a.xlog',
      'b.zip',
    ]);
    expect(
      service.requests.every((request) => request.outputDirectory == 'chosen'),
      isTrue,
    );
    expect(
      controller.tasks.every((task) => task.status == DecodeTaskStatus.success),
      isTrue,
    );
    expect(controller.busy, isFalse);
  });

  test('Validates private keys before starting work', () async {
    final service = FakeLogFileService();
    final controller = DecoderController(service: service);
    addTearDown(controller.dispose);
    await controller.decodePaths(['a.xlog'], privateKeyHex: 'invalid');
    expect(controller.configurationError, isNotNull);
    expect(service.requests, isEmpty);
    expect(controller.tasks, isEmpty);
  });

  test(
    'Busy state prevents overlapping work and configuration changes',
    () async {
      final gate = Completer<DecodeBatchResult>();
      final service = FakeLogFileService(handler: (_) => gate.future);
      final controller = DecoderController(service: service);
      addTearDown(controller.dispose);
      final work = controller.decodePaths(['a.xlog']);
      expect(controller.busy, isTrue);
      controller.setOutputDirectory('ignored');
      controller.clear();
      await controller.decodePaths(['ignored.xlog']);
      expect(controller.tasks, hasLength(1));
      expect(controller.outputDirectory, isNull);
      gate.complete(successfulBatch());
      await work;
      expect(controller.busy, isFalse);
    },
  );

  test(
    'Errors do not stop later inputs and partial recovery is visible',
    () async {
      final service = FakeLogFileService(
        handler: (request) async {
          if (request.inputPath == 'bad.zip') {
            throw const FormatException('ZIP 已损坏');
          }
          return DecodeBatchResult([
            const DecodedFile(
              sourceName: 'good.xlog',
              outputPath: 'good.txt.log',
              issues: ['gap'],
            ),
            const DecodedFile(sourceName: 'bad.xlog', error: 'no content'),
          ]);
        },
      );
      final controller = DecoderController(service: service);
      addTearDown(controller.dispose);
      await controller.decodePaths(['bad.zip', 'mixed.zip']);
      expect(controller.tasks.map((task) => task.status), [
        DecodeTaskStatus.failure,
        DecodeTaskStatus.warning,
      ]);
      expect(controller.tasks.first.error, 'ZIP 已损坏');
    },
  );
}
