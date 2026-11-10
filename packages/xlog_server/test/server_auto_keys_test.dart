import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:test/test.dart';
import 'package:xlog_server/xlog_server.dart';

import '../../xlog_decode/test/support/encrypted_fixture_builder.dart';

void main() {
  final fixture =
      jsonDecode(
            File(
              '../xlog_decode/test/fixtures/mars_reference.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;
  List<int> unhex(String value) => [
    for (var i = 0; i < value.length; i += 2)
      int.parse(value.substring(i, i + 2), radix: 16),
  ];
  final privateKey = fixture['privateKey'] as String;
  final wrongKey = '01' * 32;
  final expected = unhex(fixture['plain'] as String);
  final alternatePlain = utf8.encode('[I] another configured server key\n');
  final alternate = encryptedFrame(
    7,
    fixturePrivateKeyB,
    plain: alternatePlain,
  );
  List<int> frame(String magic) => unhex(fixture['modern'][magic] as String);
  late Directory data;
  late XlogServer server;
  late HttpClient client;

  setUp(() async {
    data = await Directory.systemTemp.createTemp('xlog-auto-keys-');
    client = HttpClient();
    server = await XlogServer.bind(ServerConfig(dataDirectory: data), port: 0);
  });
  tearDown(() async {
    client.close(force: true);
    await server.close();
    await data.delete(recursive: true);
  });

  Future<void> configure(List<String> candidates) async {
    await server.close();
    server = await XlogServer.bind(
      ServerConfig(
        dataDirectory: data,
        keys: {
          for (var i = 0; i < candidates.length; i++)
            'private-$i': ServerKey('Private candidate $i', candidates[i]),
        },
      ),
      port: 0,
    );
  }

  Future<(int, List<int>)> request(String path, {List<int>? bytes}) async {
    final call = await client.openUrl(
      bytes == null ? 'GET' : 'POST',
      Uri.parse('http://127.0.0.1:${server.port}$path'),
    );
    if (bytes != null) call.add(bytes);
    final response = await call.close();
    return (
      response.statusCode,
      await response.fold<List<int>>([], (all, chunk) => all..addAll(chunk)),
    );
  }

  Map<String, dynamic> object(List<int> bytes) =>
      jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;

  Future<Map<String, dynamic>> submit(
    List<int> bytes, {
    String name = 'auto.xlog',
  }) async {
    final response = await request('/api/jobs?filename=$name', bytes: bytes);
    expect(response.$1, 202);
    final accepted = object(response.$2);
    return () async {
      while (true) {
        final response = await request('/api/jobs/${accepted['id']}');
        expect(response.$1, 200);
        final job = object(response.$2);
        if (['success', 'warning', 'failure'].contains(job['status'])) {
          return job;
        }
      }
    }().timeout(const Duration(seconds: 10));
  }

  Future<void> expectDecoded(
    List<int> bytes,
    List<int> plain, {
    int blocks = 1,
  }) async {
    final job = await submit(bytes);
    expect(job['status'], anyOf('success', 'warning'));
    expect(job['blockCount'], blocks);
    expect(job['outputBytes'], plain.length);
    expect(job['downloadUrl'], '/api/jobs/${job['id']}/download');
    final response = await request(job['downloadUrl'] as String);
    expect(response.$1, 200);
    expect(response.$2, plain);
    for (final secret in [privateKey, wrongKey, fixturePrivateKeyB]) {
      expect(jsonEncode(job), isNot(contains(secret)));
    }
    expect(jsonEncode(job), isNot(contains('Private candidate')));
    expect(jsonEncode(job), isNot(contains(data.path)));
  }

  Future<void> expectFailed(
    List<int> bytes, {
    String name = 'auto.xlog',
  }) async {
    final job = await submit(bytes, name: name);
    expect(job['status'], 'failure');
    expect(job['error']['code'], 'decode_failed');
    expect(job.containsKey('downloadUrl'), isFalse);
    for (final secret in [privateKey, wrongKey, fixturePrivateKeyB]) {
      expect(jsonEncode(job), isNot(contains(secret)));
    }
    expect(jsonEncode(job), isNot(contains('Private candidate')));
    expect(jsonEncode(job), isNot(contains(data.path)));
    expect(await Directory('${data.path}/${job['id']}').exists(), isFalse);
    expect((await request('/api/jobs/${job['id']}/download')).$1, 409);
  }

  test(
    'plain formats need no configured key and no upload selection',
    () async {
      for (final magic in ['09', '0d']) {
        await expectDecoded(frame(magic), expected);
      }
    },
  );

  test(
    'encrypted formats automatically skip a wrong first candidate',
    () async {
      await configure([wrongKey, privateKey]);
      for (final magic in ['07', '0c']) {
        await expectDecoded(frame(magic), expected);
      }
    },
  );

  test(
    'mixed plain and encrypted blocks use a single streaming decode',
    () async {
      await configure([wrongKey, privateKey]);
      await expectDecoded(
        [...frame('09'), ...frame('07'), ...frame('0d'), ...frame('0c')],
        [for (var i = 0; i < 4; i++) ...expected],
        blocks: 4,
      );
    },
  );

  test(
    'one log can alternate between multiple configured private keys',
    () async {
      await configure([wrongKey, privateKey, fixturePrivateKeyB]);
      await expectDecoded(
        [...frame('09'), ...frame('07'), ...alternate],
        [...expected, ...expected, ...alternatePlain],
        blocks: 3,
      );
    },
  );

  test(
    'ZIP members automatically decode plain and encrypted formats',
    () async {
      await configure([wrongKey, privateKey, fixturePrivateKeyB]);
      final archive = Archive()
        ..add(ArchiveFile.bytes('plain.xlog', frame('09')))
        ..add(ArchiveFile.bytes('nested/encrypted.xlog', frame('07')))
        ..add(
          ArchiveFile.bytes(
            'zstd.bin',
            encryptedFrame(12, fixturePrivateKeyB, plain: alternatePlain),
          ),
        );
      final job = await submit(
        ZipEncoder().encodeBytes(archive),
        name: 'mixed.zip',
      );
      expect(job['status'], 'success');
      expect(job['blockCount'], 3);
      expect(job['outputBytes'], expected.length * 2 + alternatePlain.length);
      final response = await request(job['downloadUrl'] as String);
      expect(response.$1, 200);
      final decoded = ZipDecoder().decodeBytes(response.$2, verify: true);
      expect(decoded.files.map((entry) => entry.name), [
        '1_plain.log',
        '2_encrypted.log',
        '3_zstd.log',
      ]);
      expect(decoded.files[0].content, expected);
      expect(decoded.files[1].content, expected);
      expect(decoded.files[2].content, alternatePlain);
      expect(jsonEncode(job), isNot(contains(privateKey)));
      expect(jsonEncode(job), isNot(contains(wrongKey)));
      expect(jsonEncode(job), isNot(contains(fixturePrivateKeyB)));
    },
  );

  test(
    'missing keys fail instead of returning ciphertext or partial plain output',
    () async {
      await expectFailed(frame('07'));
      await expectFailed([...frame('09'), ...frame('07')]);
    },
  );

  test(
    'all wrong candidates fail and remove previously decoded output',
    () async {
      await configure([wrongKey]);
      await expectFailed(frame('0c'));
      await expectFailed([...frame('09'), ...frame('07')]);
    },
  );

  test(
    'ZIP key failure removes earlier plain members and partial output archive',
    () async {
      final archive = Archive()
        ..add(ArchiveFile.bytes('plain.xlog', frame('09')))
        ..add(ArchiveFile.bytes('encrypted.xlog', frame('07')));
      await expectFailed(
        ZipEncoder().encodeBytes(archive),
        name: 'missing-key.zip',
      );
    },
  );

  test('a missing second key fails a mixed file and ZIP atomically', () async {
    await configure([privateKey]);
    await expectFailed([...frame('09'), ...frame('07'), ...alternate]);
    final archive = Archive()
      ..add(ArchiveFile.bytes('first.xlog', frame('07')))
      ..add(ArchiveFile.bytes('second.xlog', alternate));
    await expectFailed(
      ZipEncoder().encodeBytes(archive),
      name: 'missing-second.zip',
    );
  });

  test(
    'CLI key failures keep candidate secrets out of responses and logs',
    () async {
      final configuration = File('${data.path}/cli.json');
      final secrets = [wrongKey, fixturePrivateKeyB];
      await configuration.writeAsString(
        jsonEncode({
          'port': 0,
          'dataDirectory': '${data.path}/cli-data',
          'keys': {
            for (var i = 0; i < secrets.length; i++)
              'candidate-$i': {'privateKeyHex': secrets[i]},
          },
        }),
      );
      final process = await Process.start(
        Platform.resolvedExecutable,
        [
          '--packages=${File('.dart_tool/package_config.json').absolute.path}',
          'bin/server.dart',
          '--config',
          configuration.path,
        ],
        environment: Map.fromEntries(
          Platform.environment.entries.where(
            (entry) =>
                !entry.key.startsWith('XLOG_') &&
                entry.key != 'PORT' &&
                entry.key != 'HOST',
          ),
        ),
        includeParentEnvironment: false,
      );
      final logs = <String>[];
      final listening = Completer<int>();
      final outputDone = process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .forEach((line) {
            logs.add(line);
            final match = RegExp(
              r'listening on http://127\.0\.0\.1:(\d+)',
            ).firstMatch(line);
            if (match != null && !listening.isCompleted) {
              listening.complete(int.parse(match.group(1)!));
            }
          });
      final errorDone = process.stderr
          .transform(utf8.decoder)
          .forEach(logs.add);
      try {
        final port = await listening.future.timeout(
          const Duration(seconds: 10),
        );
        Future<Map<String, dynamic>> call(
          String path, {
          List<int>? bytes,
        }) async {
          final outgoing = await client.openUrl(
            bytes == null ? 'GET' : 'POST',
            Uri.parse('http://127.0.0.1:$port$path'),
          );
          if (bytes != null) outgoing.add(bytes);
          final incoming = await outgoing.close();
          expect(incoming.statusCode, bytes == null ? 200 : 202);
          return jsonDecode(await utf8.decoder.bind(incoming).join())
              as Map<String, dynamic>;
        }

        final accepted = await call(
          '/api/jobs?filename=unmatched.xlog',
          bytes: frame('07'),
        );
        final job = await () async {
          while (true) {
            final value = await call('/api/jobs/${accepted['id']}');
            if (value['status'] == 'failure') return value;
            if (['success', 'warning'].contains(value['status'])) {
              fail('An unmatched encrypted log must fail');
            }
          }
        }().timeout(const Duration(seconds: 10));
        expect(job['error']['code'], 'decode_failed');
        for (final secret in secrets) {
          expect(jsonEncode(job), isNot(contains(secret)));
        }
      } finally {
        process.kill(ProcessSignal.sigint);
        try {
          expect(await process.exitCode.timeout(const Duration(seconds: 5)), 0);
        } on TimeoutException {
          process.kill(ProcessSignal.sigkill);
          await process.exitCode;
          rethrow;
        }
        await Future.wait([outputDone, errorDone]);
      }
      for (final secret in secrets) {
        expect(logs.join('\n'), isNot(contains(secret)));
      }
    },
  );
}
