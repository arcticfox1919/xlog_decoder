import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:xlog_decoder/features/decoder/data/log_file_service.dart';
import 'package:xlog_decoder/features/decoder/domain/decode_models.dart';

import 'support/fixtures.dart';

void main() {
  const service = LocalLogFileService();
  late Directory sandbox;
  final expected = unhex(reference['plain'] as String);

  setUp(
    () async =>
        sandbox = await Directory.systemTemp.createTemp('xlog_gui_test_'),
  );
  tearDown(() async => sandbox.delete(recursive: true));

  Future<File> input(String name, List<int> bytes) async =>
      File(p.join(sandbox.path, name))..writeAsBytesSync(bytes);

  test(
    'Single file writes .log beside the source without changing it',
    () async {
      final source = await input('sample.xlog', modern('09'));
      final result = await service.decode(
        DecodeRequest(inputPath: source.path),
      );
      final output = result.files.single;
      expect(output.outputPath, p.join(sandbox.path, 'sample.log'));
      expect(await File(output.outputPath!).readAsBytes(), expected);
      expect(await source.readAsBytes(), modern('09'));
    },
  );

  for (final magic in ['07', '0c']) {
    test(
      'Encrypted $magic uses the configured key and output directory',
      () async {
        final source = await input('encrypted.xlog', modern(magic));
        final directory = p.join(sandbox.path, 'output');
        final result = await service.decode(
          DecodeRequest(
            inputPath: source.path,
            outputDirectory: directory,
            privateKeyHex: reference['privateKey'] as String,
          ),
        );
        expect(result.successCount, 1);
        expect(
          await File(p.join(directory, 'encrypted.log')).readAsBytes(),
          expected,
        );
      },
    );
  }

  test(
    'Existing output is preserved and the new output gets a number',
    () async {
      final source = await input('app.xlog', modern('09'));
      final existing = await input('app.log', [65]);
      final existingNumbered = await input('app1.log', [66]);
      final result = await service.decode(
        DecodeRequest(inputPath: source.path),
      );
      expect(result.files.single.outputPath, p.join(sandbox.path, 'app2.log'));
      expect(await existing.readAsBytes(), [65]);
      expect(await existingNumbered.readAsBytes(), [66]);
    },
  );

  test(
    'ZIP groups decoded logs in a named folder, flattens names, and avoids traversal',
    () async {
      final archive = Archive()
        ..add(ArchiveFile.bytes('one/app.xlog', modern('09')))
        ..add(ArchiveFile.bytes('two/app.xlog', modern('0d')))
        ..add(ArchiveFile.bytes('../outside.log', modern('08')))
        ..add(ArchiveFile.bytes('README.txt', [65]))
        ..add(ArchiveFile.bytes('__MACOSX/meta.xlog', [65]));
      final source = await input('logs.zip', ZipEncoder().encodeBytes(archive));
      final result = await service.decode(
        DecodeRequest(inputPath: source.path),
      );
      expect(result.successCount, 3);
      expect(result.skippedEntries, 2);
      expect(result.files.map((file) => p.basename(file.outputPath!)), [
        'app.log',
        'app1.log',
        'outside.log',
      ]);
      for (final file in result.files) {
        expect(p.dirname(file.outputPath!), p.join(sandbox.path, 'logs'));
        expect(await File(file.outputPath!).readAsBytes(), expected);
      }
      expect(await Directory(p.join(sandbox.path, 'one')).exists(), isFalse);
    },
  );

  test(
    'ZIP writes to the selected directory and continues after a failed log',
    () async {
      final archive = Archive()
        ..add(ArchiveFile.bytes('bad.xlog', [255]))
        ..add(ArchiveFile.bytes('good.xlog', modern('09')));
      final source = await input(
        'mixed.zip',
        ZipEncoder().encodeBytes(archive),
      );
      final directory = p.join(sandbox.path, 'chosen');
      final result = await service.decode(
        DecodeRequest(inputPath: source.path, outputDirectory: directory),
      );
      expect(result.successCount, 1);
      expect(result.failureCount, 1);
      expect(result.files.first.error, isNotNull);
      expect(
        await File(p.join(directory, 'mixed', 'good.log')).readAsBytes(),
        expected,
      );
      expect(
        await File(p.join(directory, 'mixed', 'bad.log')).exists(),
        isFalse,
      );
    },
  );

  test(
    'Repeated ZIP decoding creates a new folder and preserves prior output',
    () async {
      final source = await input(
        'logs.zip',
        ZipEncoder().encodeBytes(
          Archive()..add(ArchiveFile.bytes('app.xlog', modern('09'))),
        ),
      );
      final first = await service.decode(DecodeRequest(inputPath: source.path));
      final second = await service.decode(
        DecodeRequest(inputPath: source.path),
      );
      final third = await service.decode(DecodeRequest(inputPath: source.path));
      expect(
        third.files.single.outputPath,
        p.join(sandbox.path, 'logs2', 'app.log'),
      );
      expect(
        first.files.single.outputPath,
        p.join(sandbox.path, 'logs', 'app.log'),
      );
      expect(
        second.files.single.outputPath,
        p.join(sandbox.path, 'logs1', 'app.log'),
      );
      expect(
        await File(first.files.single.outputPath!).readAsBytes(),
        expected,
      );
      expect(
        await File(second.files.single.outputPath!).readAsBytes(),
        expected,
      );
    },
  );

  test('ZIP folder naming skips existing files too', () async {
    final existing = await input('logs', [65]);
    final source = await input(
      'logs.zip',
      ZipEncoder().encodeBytes(
        Archive()..add(ArchiveFile.bytes('app.xlog', modern('09'))),
      ),
    );
    final result = await service.decode(DecodeRequest(inputPath: source.path));
    expect(
      result.files.single.outputPath,
      p.join(sandbox.path, 'logs1', 'app.log'),
    );
    expect(await existing.readAsBytes(), [65]);
  });

  test('A .log input is preserved and decoded to a numbered .log', () async {
    final source = await input('app.log', modern('09'));
    final result = await service.decode(DecodeRequest(inputPath: source.path));
    expect(result.files.single.outputPath, p.join(sandbox.path, 'app1.log'));
    expect(await source.readAsBytes(), modern('09'));
    expect(await File(result.files.single.outputPath!).readAsBytes(), expected);
  });

  test('Missing key or invalid input produces no empty output', () async {
    for (final bytes in [
      modern('07'),
      [255],
    ]) {
      final source = await input('bad.xlog', bytes);
      final result = await service.decode(
        DecodeRequest(inputPath: source.path),
      );
      expect(result.failureCount, 1);
      expect(result.files.single.error, isNotNull);
      expect(await File(p.join(sandbox.path, 'bad.log')).exists(), isFalse);
    }
  });

  test('ZIP without logs reports a useful error', () async {
    final source = await input(
      'empty.zip',
      ZipEncoder().encodeBytes(
        Archive()..add(ArchiveFile.string('README.txt', 'readme')),
      ),
    );
    await expectLater(
      service.decode(DecodeRequest(inputPath: source.path)),
      throwsFormatException,
    );
  });

  test('Missing files and corrupted ZIPs fail cleanly', () async {
    await expectLater(
      service.decode(
        DecodeRequest(inputPath: p.join(sandbox.path, 'missing.xlog')),
      ),
      throwsFormatException,
    );
    final source = await input('broken.zip', [1, 2, 3]);
    await expectLater(
      service.decode(DecodeRequest(inputPath: source.path)),
      throwsA(isA<Exception>()),
    );
  });
}
