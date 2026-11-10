import 'dart:async';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:test/test.dart';
import 'package:xlog_decode/xlog_decode.dart';

import 'support/fixtures.dart';

Stream<List<int>> _pieces(List<int> bytes, int size) async* {
  for (var offset = 0; offset < bytes.length; offset += size) {
    final end = offset + size < bytes.length ? offset + size : bytes.length;
    yield bytes.sublist(offset, end);
  }
}

Object _blockValues(XlogBlock block) => (
  block.offset,
  block.magic,
  block.sequence,
  block.beginHour,
  block.endHour,
  block.payloadLength,
  block.decodedLength,
);

void main() {
  final key = reference['privateKey'] as String;

  test(
    'Streaming all Mars formats preserves byte results and metadata',
    () async {
      final input = Uint8List.fromList([
        for (final magic in ['06', '07', '08', '09', '0a', '0b', '0c', '0d'])
          ...modern(magic),
      ]);
      final decoder = XlogDecoder(privateKeyHex: key, strict: true);
      final expected = decoder.decode(input);
      final output = BytesBuilder(copy: false);
      final blocks = <XlogBlock>[];
      final issues = <XlogIssue>[];
      final summary = await decoder.decodeTo(
        _pieces(input, 7),
        onData: output.add,
        onBlock: blocks.add,
        onIssue: issues.add,
      );
      expect(output.takeBytes(), expected.bytes);
      expect(blocks.map(_blockValues), expected.blocks.map(_blockValues));
      expect(issues.map((issue) => issue.toString()), isEmpty);
      expect(summary.inputBytes, input.length);
      expect(summary.outputBytes, expected.bytes.length);
      expect(summary.blockCount, expected.blocks.length);
      expect(summary.issueCount, 0);
    },
  );

  test(
    'Single-byte fragments cross every header and payload boundary',
    () async {
      final input = Uint8List.fromList([
        ...modern('07'),
        ...modern('0d'),
        ...frame(8, [65, 66, 67]),
      ]);
      final decoder = XlogDecoder(privateKeyHex: key, strict: true);
      final output = BytesBuilder(copy: false);
      final summary = await decoder.decodeTo(
        _pieces(input, 1),
        onData: output.add,
      );
      expect(output.takeBytes(), decoder.decode(input).bytes);
      expect(summary.blockCount, 3);
      expect(summary.issueCount, 0);
    },
  );

  test(
    'A single complete frame is accepted only at actual input EOF',
    () async {
      final source = StreamController<List<int>>();
      final output = BytesBuilder(copy: false);
      final input = frame(8, [65]);
      final work = XlogDecoder(
        strict: true,
      ).decodeTo(source.stream, onData: output.add);
      source.add(input);
      await Future<void>.delayed(Duration.zero);
      expect(output.length, 0, reason: 'A chunk boundary is not an input EOF.');
      await source.close();
      final summary = await work;
      expect(output.takeBytes(), [65]);
      expect(summary.blockCount, 1);
      expect(summary.inputBytes, input.length);
    },
  );

  test(
    'Initial search rejects an isolated frame before a valid EOF frame',
    () async {
      final input = Uint8List.fromList([
        ...frame(8, [65]),
        255,
        ...frame(8, [66]),
      ]);
      final expected = XlogDecoder().decode(input);
      final output = BytesBuilder(copy: false);
      final issues = <XlogIssue>[];
      final summary = await XlogDecoder().decodeTo(
        _pieces(input, 1),
        onData: output.add,
        onIssue: issues.add,
      );
      expect(output.takeBytes(), [66]);
      expect(
        issues.map((issue) => issue.toString()),
        expected.issues.map((issue) => issue.toString()),
      );
      expect(summary.blockCount, 1);
    },
  );

  test(
    'Recovery and trailing zero padding match byte-oriented decoding',
    () async {
      final input = Uint8List.fromList([
        255,
        ...frame(8, [65], sequence: 1),
        ...frame(8, [66], sequence: 3),
        255,
        254,
        ...frame(8, [67], sequence: 5),
        ...List<int>.filled(100, 0),
      ]);
      final decoder = XlogDecoder();
      final expected = decoder.decode(input);
      final output = BytesBuilder(copy: false);
      final issues = <XlogIssue>[];
      final blocks = <XlogBlock>[];
      final summary = await decoder.decodeTo(
        _pieces(input, 11),
        onData: output.add,
        onIssue: issues.add,
        onBlock: blocks.add,
      );
      expect(output.takeBytes(), expected.bytes);
      expect(
        issues.map((issue) => issue.toString()),
        expected.issues.map((issue) => issue.toString()),
      );
      expect(blocks.map(_blockValues), expected.blocks.map(_blockValues));
      expect(summary.issueCount, expected.issues.length);
      expect(summary.inputBytes, input.length);
    },
  );

  test(
    'Checksum failure never writes partially decompressed block bytes',
    () async {
      final damaged = ZstdEncoder().encodeBytes(
        List<int>.filled(2048, 88),
        checksum: true,
      );
      damaged[damaged.length - 1] ^= 255;
      final input = Uint8List.fromList([
        ...frame(8, [65]),
        ...frame(13, damaged),
        ...frame(8, [66]),
      ]);
      final output = BytesBuilder(copy: false);
      final issues = <XlogIssue>[];
      final summary = await XlogDecoder().decodeTo(
        _pieces(input, 17),
        onData: output.add,
        onIssue: issues.add,
      );
      expect(output.takeBytes(), [65, 66]);
      expect(issues.single.kind, XlogIssueKind.payload);
      expect(summary.blockCount, 2);
      expect(summary.issueCount, 1);
    },
  );

  test('A slow output callback stops requesting later input frames', () async {
    final blocked = Completer<void>();
    final release = Completer<void>();
    var reads = 0;
    var writes = 0;
    Stream<List<int>> source() async* {
      for (var i = 0; i < 5; i++) {
        reads++;
        yield frame(8, [65]);
      }
    }

    final work = XlogDecoder().decodeTo(
      source(),
      onData: (_) async {
        writes++;
        if (writes == 1) {
          blocked.complete();
          await release.future;
        }
      },
    );
    await blocked.future.timeout(const Duration(seconds: 5));
    await Future<void>.delayed(Duration.zero);
    expect(
      reads,
      lessThanOrEqualTo(2),
      reason: 'Startup needs two frames; a blocked sink prevents read-ahead.',
    );
    expect(writes, 1);
    release.complete();
    expect((await work).blockCount, 5);
  });

  test('Output chunks obey the configured write size', () async {
    final input = frame(8, List<int>.generate(100, (i) => i));
    final output = BytesBuilder(copy: false);
    final lengths = <int>[];
    final summary = await XlogDecoder().decodeTo(
      _pieces(input, 23),
      onData: (bytes) {
        lengths.add(bytes.length);
        output.add(bytes);
      },
      options: const XlogStreamOptions(outputChunkBytes: 7),
    );
    expect(lengths, everyElement(inInclusiveRange(1, 7)));
    expect(lengths.length, greaterThan(1));
    expect(output.takeBytes(), List<int>.generate(100, (i) => i));
    expect(summary.outputBytes, 100);
  });

  test(
    'Input chunk and frame sizes have independent resource limits',
    () async {
      final largeFrame = frame(8, List<int>.filled(200, 65));
      await expectLater(
        XlogDecoder().decodeTo(
          _pieces(largeFrame, 32),
          onData: (_) {},
          options: const XlogStreamOptions(maxFrameBytes: 128),
        ),
        throwsA(isA<XlogResourceLimitException>()),
      );
      await expectLater(
        XlogDecoder().decodeTo(
          Stream<List<int>>.value(frame(8, [65])),
          onData: (_) {},
          options: const XlogStreamOptions(maxInputChunkBytes: 32),
        ),
        throwsA(isA<XlogResourceLimitException>()),
      );
    },
  );

  test(
    'A small compressed input cannot exceed the decoded block budget',
    () async {
      final input = frame(9, Deflate(List<int>.filled(1024, 65)).getBytes());
      final output = BytesBuilder(copy: false);
      await expectLater(
        XlogDecoder().decodeTo(
          _pieces(input, 23),
          onData: output.add,
          options: const XlogStreamOptions(maxDecodedBlockBytes: 32),
        ),
        throwsA(isA<XlogResourceLimitException>()),
      );
      expect(output.length, 0);
    },
  );

  test('The combined output budget is enforced across frames', () async {
    final input = Uint8List.fromList([
      ...frame(8, [65, 66]),
      ...frame(8, [67]),
    ]);
    final output = BytesBuilder(copy: false);
    await expectLater(
      XlogDecoder(
        maxOutputBytes: 2,
      ).decodeTo(_pieces(input, 19), onData: output.add),
      throwsA(isA<XlogResourceLimitException>()),
    );
    expect(output.takeBytes(), [65, 66]);
  });

  test('Oversized Zstandard window is rejected as a payload issue', () async {
    // A valid one-byte raw frame declaring a 2 KiB decompression window.
    final input = frame(13, [0x28, 0xb5, 0x2f, 0xfd, 0, 8, 9, 0, 0, 65]);
    final output = BytesBuilder(copy: false);
    final issues = <XlogIssue>[];
    final summary = await XlogDecoder().decodeTo(
      _pieces(input, 13),
      onData: output.add,
      onIssue: issues.add,
      options: const XlogStreamOptions(maxZstdWindowBytes: 1024),
    );
    expect(output.length, 0);
    expect(issues.single.kind, XlogIssueKind.payload);
    expect(summary.blockCount, 0);
    expect(summary.issueCount, 1);
    await expectLater(
      XlogDecoder(strict: true).decodeTo(
        _pieces(input, 13),
        onData: (_) {},
        options: const XlogStreamOptions(maxZstdWindowBytes: 1024),
      ),
      throwsA(isA<XlogDecodeException>()),
    );
  });

  test(
    'Long inputs retain bounded parser memory while callbacks count metadata',
    () async {
      final block = frame(8, [65], sequence: 2);
      Future<XlogStreamSummary> run(int count) async {
        var emittedBytes = 0;
        var emittedBlocks = 0;
        var emittedIssues = 0;
        Stream<List<int>> input() async* {
          for (var i = 0; i < count; i++) {
            yield block;
          }
        }

        final summary = await XlogDecoder().decodeTo(
          input(),
          onData: (bytes) => emittedBytes += bytes.length,
          onBlock: (_) => emittedBlocks++,
          onIssue: (_) => emittedIssues++,
          options: const XlogStreamOptions(
            maxFrameBytes: 128,
            maxInputChunkBytes: 128,
          ),
        );
        expect(emittedBytes, count);
        expect(emittedBlocks, count);
        expect(emittedIssues, count - 1);
        expect(summary.inputBytes, block.length * count);
        expect(summary.outputBytes, count);
        expect(summary.blockCount, count);
        expect(summary.issueCount, count - 1);
        return summary;
      }

      final short = await run(8);
      final long = await run(4000);
      expect(
        long.peakBufferedBytes,
        lessThanOrEqualTo(short.peakBufferedBytes + 128),
      );
      expect(long.peakBufferedBytes, lessThanOrEqualTo(3 * 128));
    },
  );

  test(
    'Input errors preserve identity and cancel the upstream subscription',
    () async {
      var canceled = false;
      final source = StreamController<List<int>>(
        onCancel: () => canceled = true,
      );
      final failure = StateError('upstream failed');
      final work = XlogDecoder().decodeTo(source.stream, onData: (_) {});
      final check = expectLater(work, throwsA(same(failure)));
      source.addError(failure);
      await check;
      expect(canceled, isTrue);
      await source.close();
    },
  );

  test(
    'Output errors preserve identity and cancel the upstream subscription',
    () async {
      var canceled = false;
      final source = StreamController<List<int>>(
        onCancel: () => canceled = true,
      );
      final failure = StateError('downstream failed');
      final work = XlogDecoder().decodeTo(
        source.stream,
        onData: (_) async => throw failure,
      );
      final check = expectLater(work, throwsA(same(failure)));
      source.add([
        ...frame(8, [65]),
        ...frame(8, [66]),
      ]);
      await check;
      expect(canceled, isTrue);
      await source.close();
    },
  );

  test(
    'Legacy C frames keep XOR, chunking, and header semantics when streamed',
    () async {
      final plain = Uint8List.fromList(
        List<int>.generate(100, (i) => 32 + i % 64),
      );
      final bytes = BytesBuilder(copy: false);
      for (var magic = 1; magic <= 5; magic++) {
        final sequence = 30 + magic;
        var payload = magic == 1 || magic == 3
            ? plain
            : Deflate(plain).getBytes();
        final xorKey =
            0xcc ^ ((magic <= 2 ? payload.length : sequence) & 255) ^ magic;
        payload = Uint8List.fromList([
          for (final byte in payload) byte ^ xorKey,
        ]);
        if (magic == 5) {
          final split = payload.length ~/ 2;
          payload = Uint8List.fromList([
            split & 255,
            split >> 8,
            ...payload.sublist(0, split),
            (payload.length - split) & 255,
            (payload.length - split) >> 8,
            ...payload.sublist(split),
          ]);
        }
        bytes.add(
          frame(
            magic,
            payload,
            sequence: sequence,
            headerSize: magic <= 2 ? 5 : 9,
          ),
        );
      }
      final input = bytes.takeBytes();
      final decoder = XlogDecoder(
        legacyFormat: XlogLegacyFormat.c,
        strict: true,
      );
      final expected = decoder.decode(input);
      final output = BytesBuilder(copy: false);
      final blocks = <XlogBlock>[];
      final summary = await decoder.decodeTo(
        _pieces(input, 3),
        onData: output.add,
        onBlock: blocks.add,
      );
      expect(output.takeBytes(), expected.bytes);
      expect(expected.bytes, [for (var i = 0; i < 5; i++) ...plain]);
      expect(blocks.map(_blockValues), expected.blocks.map(_blockValues));
      expect(summary.blockCount, 5);
      expect(summary.issueCount, 0);
    },
  );

  test('Strict streaming rejects malformed framing and payloads', () async {
    for (final (input, kind) in [
      (Uint8List.fromList([255]), XlogIssueKind.framing),
      (frame(9, [255]), XlogIssueKind.payload),
    ]) {
      var writes = 0;
      await expectLater(
        XlogDecoder(
          strict: true,
        ).decodeTo(_pieces(input, 1), onData: (_) => writes++),
        throwsA(
          isA<XlogDecodeException>().having(
            (error) => error.issue.kind,
            'issue kind',
            kind,
          ),
        ),
      );
      expect(writes, 0);
    }
  });

  test(
    'Empty stream and empty events finish without output or diagnostics',
    () async {
      var writes = 0;
      var issues = 0;
      var blocks = 0;
      final summary = await XlogDecoder(strict: true).decodeTo(
        Stream<List<int>>.fromIterable([[], [], []]),
        onData: (_) => writes++,
        onIssue: (_) => issues++,
        onBlock: (_) => blocks++,
      );
      expect(writes, 0);
      expect(issues, 0);
      expect(blocks, 0);
      expect(summary.inputBytes, 0);
      expect(summary.outputBytes, 0);
      expect(summary.blockCount, 0);
      expect(summary.issueCount, 0);
      expect(summary.peakBufferedBytes, 0);
    },
  );

  test(
    'Invalid stream options are rejected before subscribing to input',
    () async {
      for (final options in const [
        XlogStreamOptions(maxFrameBytes: 0),
        XlogStreamOptions(maxDecodedBlockBytes: 0),
        XlogStreamOptions(maxInputChunkBytes: 0),
        XlogStreamOptions(outputChunkBytes: 0),
        XlogStreamOptions(maxZstdWindowBytes: 0),
        XlogStreamOptions(maxZstdWindowBytes: 0x80000001),
        XlogStreamOptions(maxCachedKeys: -1),
      ]) {
        var subscriptions = 0;
        final source = StreamController<List<int>>(
          onListen: () => subscriptions++,
        );
        await expectLater(
          XlogDecoder().decodeTo(
            source.stream,
            onData: (_) {},
            options: options,
          ),
          throwsArgumentError,
        );
        expect(subscriptions, 0);
        // This idle controller has no subscriber to complete its done future.
        unawaited(source.close());
      }
    },
  );

  test(
    'Cancellation failure cannot replace the original output error',
    () async {
      final primary = StateError('output failed');
      final cancellation = StateError('upstream cancellation failed');
      var canceled = false;
      final source = StreamController<List<int>>(
        onCancel: () {
          canceled = true;
          throw cancellation;
        },
      );
      final work = XlogDecoder().decodeTo(
        source.stream,
        onData: (_) async => throw primary,
      );
      final check = expectLater(work, throwsA(same(primary)));
      source.add([
        ...frame(8, [65]),
        ...frame(8, [66]),
      ]);
      await check;
      expect(canceled, isTrue);
      await source.close();
    },
  );
}
