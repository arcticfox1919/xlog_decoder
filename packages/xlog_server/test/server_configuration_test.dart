import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart' as shelf;
import 'package:test/test.dart';
import 'package:xlog_server/xlog_server.dart';

void main() {
  late Directory temporary;
  late String fixtureKey;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('xlog-config-test-');
    final fixtures =
        jsonDecode(
              await File(
                '../xlog_decode/test/fixtures/mars_reference.json',
              ).readAsString(),
            )
            as Map<String, dynamic>;
    fixtureKey = fixtures['privateKey'] as String;
  });

  tearDown(() async {
    if (await temporary.exists()) await temporary.delete(recursive: true);
  });

  Directory directory(String name) => Directory(p.join(temporary.path, name));

  Future<File> keyFile(String path) async {
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsString(
      jsonEncode({
        'fixture': {
          'label': 'Public test fixture',
          'privateKeyHex': fixtureKey,
        },
      }),
    );
    return file;
  }

  test(
    'configuration takes immutable copies of key and origin collections',
    () {
      final keys = {'fixture': ServerKey('Fixture', fixtureKey)};
      final origins = {'https://client.example'};
      final config = ServerConfig(
        dataDirectory: directory('data'),
        keys: keys,
        allowedOrigins: origins,
      );

      keys.clear();
      origins.clear();
      expect(config.keys.keys, ['fixture']);
      expect(config.allowedOrigins, {'https://client.example'});
      expect(() => config.keys.clear(), throwsUnsupportedError);
      expect(
        () => config.allowedOrigins.add('https://other.example'),
        throwsUnsupportedError,
      );
    },
  );

  test('configuration rejects equal and nested public and private roots', () {
    final root = directory('root');
    final nested = Directory(p.join(root.path, 'nested'));
    for (final pair in [(root, root), (root, nested), (nested, root)]) {
      expect(
        () => ServerConfig(dataDirectory: pair.$1, webRoot: pair.$2),
        throwsArgumentError,
      );
    }
  });

  test('configuration normalizes dot segments before checking separation', () {
    expect(
      () => ServerConfig(
        dataDirectory: directory('public/../public/data'),
        webRoot: directory('public'),
      ),
      throwsArgumentError,
    );
    expect(
      ServerConfig(
        dataDirectory: directory('public-data'),
        webRoot: directory('public'),
      ),
      isA<ServerConfig>(),
    );
  });

  test(
    'create rejects realpath aliases between public and private roots',
    () async {
      final actual = await directory('actual').create();
      final alias = Link(directory('alias').path);
      await alias.create(actual.path);
      for (final pair in [
        (actual, Directory(alias.path)),
        (Directory(alias.path), actual),
      ]) {
        await expectLater(
          XlogServer.create(
            ServerConfig(dataDirectory: pair.$1, webRoot: pair.$2),
          ),
          throwsArgumentError,
        );
      }
    },
  );

  test('create rejects nested roots hidden by a symlink alias', () async {
    final public = await directory('public').create();
    final alias = Link(directory('public-alias').path);
    await alias.create(public.path);
    await expectLater(
      XlogServer.create(
        ServerConfig(
          dataDirectory: Directory(p.join(alias.path, 'data')),
          webRoot: public,
        ),
      ),
      throwsArgumentError,
    );
  });

  test('environment loads explicit settings and fixture keys', () async {
    final file = await keyFile(p.join(temporary.path, 'private', 'keys.json'));
    final options = await const ServerEnvironment().load({
      'HOST': 'localhost',
      'PORT': '0',
      'XLOG_DATA_DIR': directory('data').path,
      'XLOG_WEB_ROOT': directory('public').path,
      'XLOG_KEYS_FILE': file.path,
      'XLOG_MAX_UPLOAD_BYTES': '1234',
      'XLOG_MAX_OUTPUT_BYTES': '5678',
      'XLOG_CONCURRENCY': '1',
      'XLOG_MAX_QUEUED': '0',
      'XLOG_MAX_JOBS': '1',
      'XLOG_JOB_TTL_SECONDS': '7',
      'XLOG_ALLOWED_ORIGINS': ' https://one.example, ,https://two.example ',
    });

    expect(options.host, 'localhost');
    expect(options.port, 0);
    final config = options.config;
    expect(config.dataDirectory.path, directory('data').path);
    expect(config.webRoot!.path, directory('public').path);
    expect(config.keys['fixture']!.label, 'Public test fixture');
    expect(config.keys['fixture']!.privateKeyHex, fixtureKey);
    expect(config.maxUploadBytes, 1234);
    expect(config.maxOutputBytes, 5678);
    expect(config.maxConcurrentJobs, 1);
    expect(config.maxQueuedJobs, 0);
    expect(config.maxRetainedJobs, 1);
    expect(config.jobTtl, const Duration(seconds: 7));
    expect(config.allowedOrigins, {
      'https://one.example',
      'https://two.example',
    });
  });

  test(
    'environment uses defaults without creating a listening socket',
    () async {
      final options = await const ServerEnvironment().load({
        'XLOG_DATA_DIR': directory('data').path,
      });
      expect(options.host, '127.0.0.1');
      expect(options.port, 18781);
      expect(options.config.keys, isEmpty);
      expect(options.config.maxConcurrentJobs, 2);
      expect(options.config.maxQueuedJobs, 4);
      expect(options.config.maxRetainedJobs, 64);
      expect(options.config.jobTtl, const Duration(hours: 1));
      expect(await options.config.dataDirectory.exists(), isFalse);
    },
  );

  for (final setting in <(String, String)>[
    ('PORT', '-1'),
    ('PORT', '65536'),
    ('PORT', 'not-a-number'),
    ('XLOG_MAX_UPLOAD_BYTES', '0'),
    ('XLOG_MAX_OUTPUT_BYTES', '-1'),
    ('XLOG_CONCURRENCY', '0'),
    ('XLOG_MAX_QUEUED', '-1'),
    ('XLOG_MAX_JOBS', '1'),
    ('XLOG_JOB_TTL_SECONDS', '0'),
  ]) {
    test('environment rejects invalid ${setting.$1}=${setting.$2}', () async {
      await expectLater(
        const ServerEnvironment().load({
          'XLOG_DATA_DIR': directory('data').path,
          setting.$1: setting.$2,
        }),
        throwsA(anyOf(isA<ArgumentError>(), isA<FormatException>())),
      );
    });
  }

  test('environment rejects a key file inside the public root', () async {
    final public = directory('public');
    final file = await keyFile(p.join(public.path, 'keys.json'));
    await expectLater(
      const ServerEnvironment().load({
        'XLOG_DATA_DIR': directory('data').path,
        'XLOG_WEB_ROOT': public.path,
        'XLOG_KEYS_FILE': file.path,
      }),
      throwsArgumentError,
    );
  });

  test(
    'environment rejects public key files through key or root aliases',
    () async {
      final public = directory('public');
      final file = await keyFile(p.join(public.path, 'keys.json'));
      final keyAlias = Link(p.join(temporary.path, 'key-alias.json'));
      await keyAlias.create(file.path);
      final rootAlias = Link(directory('root-alias').path);
      await rootAlias.create(public.path);
      for (final pair in [
        (public.path, keyAlias.path),
        (rootAlias.path, file.path),
      ]) {
        await expectLater(
          const ServerEnvironment().load({
            'XLOG_DATA_DIR': directory('data').path,
            'XLOG_WEB_ROOT': pair.$1,
            'XLOG_KEYS_FILE': pair.$2,
          }),
          throwsArgumentError,
        );
      }
    },
  );

  test(
    'create serves health without a socket and close is idempotent',
    () async {
      final server = await XlogServer.create(
        ServerConfig(
          dataDirectory: directory('data'),
          maxConcurrentJobs: 1,
          maxQueuedJobs: 0,
        ),
      );
      addTearDown(server.close);
      expect(await server.config.dataDirectory.exists(), isTrue);
      expect(() => server.port, throwsStateError);
      expect(() => server.address, throwsStateError);

      final response = await server.handler(
        shelf.Request('GET', Uri.parse('http://handler.test/api/health')),
      );
      expect(response.statusCode, 200);
      expect(jsonDecode(await response.readAsString()), {
        'status': 'ok',
        'maxUploadBytes': 256 * 1024 * 1024,
        'maxConcurrentJobs': 1,
        'maxQueuedJobs': 0,
        'supportsZip': true,
      });
      final closing = server.close();
      expect(identical(closing, server.close()), isTrue);
      await closing;
      await server.close();
      expect(await server.config.dataDirectory.list().isEmpty, isTrue);
    },
  );
}
