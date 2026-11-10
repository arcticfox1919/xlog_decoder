import 'dart:async';
import 'dart:io';

import 'package:test/test.dart';
import 'package:xlog_server/src/domain/service_exception.dart';
import 'package:xlog_server/src/infrastructure/storage/file_job_storage.dart';

void main() {
  late Directory root;
  late FileJobStorage storage;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('xlog-storage-test-');
    storage = FileJobStorage(Directory('${root.path}/jobs'));
    await storage.initialize();
    await storage.createWorkspace('job-1');
  });
  tearDown(() async => root.delete(recursive: true));

  File input() => File('${root.path}/jobs/job-1/input');
  Future<void> upload(Stream<List<int>> source, {int maxBytes = 8}) =>
      storage.writeUpload(
        'job-1',
        source,
        maxBytes: maxBytes,
        timeout: const Duration(milliseconds: 30),
      );

  Matcher serviceError(ServiceError error) => isA<ServiceException>().having(
    (exception) => exception.error,
    'error',
    error,
  );

  test(
    'streams multiple chunks onto disk and accepts the exact limit',
    () async {
      await upload(
        Stream.fromIterable([
          [1, 2],
          [3, 4, 5],
          [6, 7, 8],
        ]),
      );
      expect(await input().readAsBytes(), [1, 2, 3, 4, 5, 6, 7, 8]);
      await storage.deleteInput('job-1');
      await storage.deleteInput('job-1');
      expect(await input().exists(), isFalse);
    },
  );

  test(
    'counts the whole stream and removes an oversized partial input',
    () async {
      await expectLater(
        upload(
          Stream.fromIterable([
            [1, 2, 3, 4],
            [5, 6, 7, 8, 9],
          ]),
        ),
        throwsA(serviceError(ServiceError.uploadTooLarge)),
      );
      expect(await input().exists(), isFalse);
    },
  );

  test('empty streams and zero-sized chunks leave no input file', () async {
    for (final source in [
      const Stream<List<int>>.empty(),
      Stream<List<int>>.fromIterable([[], []]),
    ]) {
      await expectLater(
        upload(source),
        throwsA(serviceError(ServiceError.emptyUpload)),
      );
      expect(await input().exists(), isFalse);
    }
  });

  test('timeout cancels the source and removes a partial upload', () async {
    var cancelled = false;
    final controller = StreamController<List<int>>(
      onCancel: () => cancelled = true,
    );
    final pending = upload(controller.stream);
    controller.add([1, 2, 3]);
    await expectLater(pending, throwsA(isA<TimeoutException>()));
    expect(cancelled, isTrue);
    expect(await input().exists(), isFalse);
    await controller.close();
  });

  test('source errors propagate and close the partial file', () async {
    final failure = StateError('source failed');
    Stream<List<int>> source() async* {
      yield [1, 2, 3];
      throw failure;
    }

    await expectLater(upload(source()), throwsA(same(failure)));
    expect(await input().exists(), isFalse);
    // Reusing the workspace also verifies the failed writer was closed.
    await upload(Stream.value([4]));
    expect(await input().readAsBytes(), [4]);
  });

  test('filesystem failures are reported instead of succeeding', () async {
    await Directory(input().path).create();
    await expectLater(
      upload(Stream.value([1])),
      throwsA(isA<FileSystemException>()),
    );
    await expectLater(
      storage.deleteInput('job-1'),
      throwsA(isA<FileSystemException>()),
    );
  });

  test(
    'reads result metadata and offers a fresh stream for each read',
    () async {
      await File('${root.path}/jobs/job-1/output.log').writeAsBytes([9, 8, 7]);
      final result = await storage.readResult('job-1', 'output.log');
      expect(result.filename, 'output.log');
      expect(result.length, 3);
      for (var i = 0; i < 2; i++) {
        expect(await result.openRead().expand((bytes) => bytes).toList(), [
          9,
          8,
          7,
        ]);
      }
      await storage.deleteWorkspace('job-1');
      await storage.deleteWorkspace('job-1');
      await expectLater(
        storage.readResult('job-1', 'output.log'),
        throwsA(serviceError(ServiceError.resultExpired)),
      );
    },
  );

  test('rejects path traversal and workspace or output symlinks', () async {
    for (final id in ['..', '../outside', '/outside', r'..\outside', '']) {
      await expectLater(storage.createWorkspace(id), throwsArgumentError);
    }
    for (final name in ['..', '../outside', '/outside', r'..\outside', '']) {
      await expectLater(storage.readResult('job-1', name), throwsArgumentError);
    }
    final outside = await Directory('${root.path}/outside').create();
    final secret = await File('${outside.path}/secret').writeAsBytes([42]);
    await Link('${root.path}/jobs/linked').create(outside.path);
    await expectLater(
      storage.createWorkspace('linked'),
      throwsA(isA<FileSystemException>()),
    );
    await expectLater(
      storage.deleteWorkspace('linked'),
      throwsA(isA<FileSystemException>()),
    );
    await Link('${root.path}/jobs/job-1/output.log').create(secret.path);
    await expectLater(
      storage.readResult('job-1', 'output.log'),
      throwsA(serviceError(ServiceError.resultExpired)),
    );
    await Link(input().path).create(secret.path);
    await expectLater(
      upload(Stream.value([1])),
      throwsA(isA<FileSystemException>()),
    );
    expect(await secret.readAsBytes(), [42]);
  });
}
