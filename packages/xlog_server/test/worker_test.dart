import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:test/test.dart';
import 'package:xlog_decode/xlog_decode.dart';
import 'package:xlog_server/src/domain/decode_task.dart';
import 'package:xlog_server/src/infrastructure/execution/isolate_job_executor.dart';
import 'package:xlog_server/src/infrastructure/execution/limited_file_output.dart';
import 'package:xlog_server/src/infrastructure/execution/zip_directory_validator.dart';
import 'package:xlog_server/src/infrastructure/execution/zip_job_decoder.dart';
import 'package:xlog_server/src/infrastructure/execution/zip_limits.dart';

void main() {
  final fixtures =
      jsonDecode(
            File(
              '../xlog_decode/test/fixtures/mars_reference.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;
  List<int> unhex(String value) => [
    for (var offset = 0; offset < value.length; offset += 2)
      int.parse(value.substring(offset, offset + 2), radix: 16),
  ];
  List<int> frame(String magic) =>
      unhex((fixtures['modern'] as Map<String, dynamic>)[magic] as String);
  final plain = unhex(fixtures['plain'] as String);
  late Directory workspace;
  setUp(() async {
    workspace = await Directory.systemTemp.createTemp('xlog-worker-test-');
  });
  tearDown(() async => workspace.delete(recursive: true));

  DecodeTask task({
    String name = 'logs.zip',
    int maxOutputBytes = 1024 * 1024,
    String? key,
  }) => DecodeTask(
    workspacePath: workspace.path,
    name: name,
    maxOutputBytes: maxOutputBytes,
    privateKeysHex: key == null ? const [] : [key],
  );
  Future<void> input(List<int> bytes) =>
      File('${workspace.path}/input').writeAsBytes(bytes);
  Future<List<String>> files() async {
    final names = await workspace
        .list()
        .map((entry) => entry.uri.pathSegments.last)
        .toList();
    names.sort();
    return names;
  }

  Uint8List zip(Archive archive) => ZipEncoder().encodeBytes(archive);
  int centralOffset(Uint8List bytes) =>
      ByteData.sublistView(bytes).getUint32(bytes.length - 6, Endian.little);

  test(
    'isolate executor decodes a real encrypted core fixture onto disk',
    () async {
      await input(frame('07'));
      final result = await const IsolateJobExecutor().execute(
        task(name: 'encrypted.xlog', key: fixtures['privateKey'] as String),
      );
      expect(result.filename, 'encrypted.log');
      expect(result.outputBytes, plain.length);
      expect(result.blockCount, 1);
      expect(result.issueCount, 0);
      expect(
        await File('${workspace.path}/${result.filename}').readAsBytes(),
        plain,
      );
    },
  );

  test('single-file output preserves long safe names', () async {
    await input(frame('09'));
    final stem = List.filled(120, 'a').join();
    final result = await const IsolateJobExecutor().execute(
      task(name: '$stem.xlog'),
    );
    expect(result.filename, '$stem.log');
  });

  test(
    'invalid single logs remove partial output instead of publishing it',
    () async {
      await input([255, 1, 2]);
      await expectLater(
        const IsolateJobExecutor().execute(task(name: 'invalid.xlog')),
        throwsA(isA<FormatException>()),
      );
      expect(await files(), ['input']);
    },
  );

  test(
    'single-file output limits remove previously written decoded blocks',
    () async {
      await input([...frame('09'), ...frame('09')]);
      await expectLater(
        const IsolateJobExecutor().execute(
          task(name: 'large.xlog', maxOutputBytes: plain.length + 1),
        ),
        throwsA(isA<XlogResourceLimitException>()),
      );
      expect(await files(), ['input']);
    },
  );

  test(
    'ZIP flattens member paths and aggregates recoverable log errors',
    () async {
      await input(
        zip(
          Archive()
            ..add(ArchiveFile.bytes('../outside.xlog', frame('09')))
            ..add(ArchiveFile.bytes(r'nested\app.bin', frame('0d')))
            ..add(ArchiveFile.bytes('bad.xlog', [255]))
            ..add(ArchiveFile.bytes('__MACOSX/hidden.xlog', frame('09')))
            ..add(ArchiveFile.bytes('.hidden.log', frame('09')))
            ..add(ArchiveFile.string('ignored.txt', 'ignored')),
        ),
      );
      final result = await const IsolateJobExecutor().execute(task());
      expect(result.filename, 'decoded.zip');
      expect(result.outputBytes, plain.length * 2);
      expect(result.blockCount, 2);
      expect(result.issueCount, 1);
      final output = ZipDecoder().decodeBytes(
        await File('${workspace.path}/decoded.zip').readAsBytes(),
        verify: true,
      );
      expect(output.files.map((entry) => entry.name), [
        '1_outside.log',
        '2_app.log',
      ]);
      for (final entry in output) {
        expect(entry.content, plain);
      }
      expect(await files(), ['decoded.zip', 'input']);
    },
  );

  test(
    'ZIP aggregate output budget fails and removes partial archive',
    () async {
      await input(
        zip(
          Archive()
            ..add(ArchiveFile.bytes('first.xlog', frame('09')))
            ..add(ArchiveFile.bytes('second.xlog', frame('09'))),
        ),
      );
      await expectLater(
        const IsolateJobExecutor().execute(
          task(maxOutputBytes: plain.length + 1),
        ),
        throwsA(isA<XlogResourceLimitException>()),
      );
      expect(await files(), ['input']);
    },
  );

  test(
    'ZIP with no recovered content removes its empty output archive',
    () async {
      await input(zip(Archive()..add(ArchiveFile.bytes('bad.xlog', [255]))));
      await expectLater(
        const IsolateJobExecutor().execute(task()),
        throwsA(isA<FormatException>()),
      );
      expect(await files(), ['input']);
    },
  );

  test('ZIP checksum failure is fatal and cleans extraction files', () async {
    final bytes = zip(
      Archive()..add(ArchiveFile.bytes('log.xlog', frame('09'))),
    );
    final view = ByteData.sublistView(bytes);
    final wrongCrc = view.getUint32(14, Endian.little) ^ 1;
    view.setUint32(14, wrongCrc, Endian.little);
    view.setUint32(centralOffset(bytes) + 16, wrongCrc, Endian.little);
    await input(bytes);
    await expectLater(
      const IsolateJobExecutor().execute(task()),
      throwsA(isA<FormatException>()),
    );
    expect(await files(), ['input']);
  });

  test('ZIP rejects symlink metadata before decoding member content', () async {
    final bytes = zip(
      Archive()..add(ArchiveFile.bytes('link.xlog', frame('09'))),
    );
    final view = ByteData.sublistView(bytes);
    view.setUint32(centralOffset(bytes) + 38, 0xa1ff << 16, Endian.little);
    await input(bytes);
    await expectLater(
      const IsolateJobExecutor().execute(task()),
      throwsA(isA<FormatException>()),
    );
    expect(await files(), ['input']);
  });

  test(
    'EOCD validation bounds entries and central-directory metadata',
    () async {
      final archive = Archive();
      for (var index = 0; index < 129; index++) {
        archive.add(ArchiveFile.string('$index.txt', 'ignored'));
      }
      await input(zip(archive));
      final file = File('${workspace.path}/input');
      expect(
        () => const ZipDirectoryValidator().validate(file),
        throwsFormatException,
      );
      final bytes = zip(
        Archive()..add(ArchiveFile.bytes('log.xlog', frame('09'))),
      );
      ByteData.sublistView(
        bytes,
      ).setUint32(bytes.length - 10, 1024 * 1024 + 1, Endian.little);
      await input(bytes);
      expect(
        () => const ZipDirectoryValidator().validate(file),
        throwsFormatException,
      );
      await input([1, 2, 3]);
      expect(
        () => const ZipDirectoryValidator().validate(file),
        throwsFormatException,
      );
    },
  );

  test(
    'ZIP entry and cumulative expansion limits clean partial files',
    () async {
      await input(
        zip(
          Archive()
            ..add(ArchiveFile.bytes('first.xlog', frame('09')))
            ..add(ArchiveFile.bytes('second.xlog', frame('09'))),
        ),
      );
      for (final limits in [
        ZipLimits(maxEntryBytes: frame('09').length - 1),
        ZipLimits(maxExpandedBytes: frame('09').length + 1),
      ]) {
        await expectLater(
          ZipJobDecoder(limits: limits).decode(task()),
          throwsA(isA<FormatException>()),
        );
        expect(await files(), ['input']);
      }
    },
  );

  test(
    'extraction output counts streamed bytes and CRC before enforcing limit',
    () async {
      final output = LimitedFileOutput('${workspace.path}/extracted', 5);
      try {
        output.writeByte(1);
        output.writeBytes([2, 3, 99], length: 2);
        output.writeStream(InputMemoryStream([4, 5]));
        expect(output.length, 5);
        expect(output.crc, getCrc32([1, 2, 3, 4, 5]));
        expect(() => output.writeBytes([6, 7]), throwsFormatException);
        expect(output.length, 5);
      } finally {
        output.closeSync();
      }
      expect(await File('${workspace.path}/extracted').readAsBytes(), [
        1,
        2,
        3,
        4,
        5,
      ]);
    },
  );
}
