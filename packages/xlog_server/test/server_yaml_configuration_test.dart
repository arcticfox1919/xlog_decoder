import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:xlog_server/xlog_server.dart';

void main() {
  late Directory temporary;
  late String privateKey;
  final loader = const ServerEnvironment();

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('xlog-yaml-test-');
    final fixture =
        jsonDecode(
              await File(
                '../xlog_decode/test/fixtures/mars_reference.json',
              ).readAsString(),
            )
            as Map<String, dynamic>;
    privateKey = fixture['privateKey'] as String;
  });
  tearDown(() async {
    if (await temporary.exists()) await temporary.delete(recursive: true);
  });

  String path(String relative) => p.join(temporary.path, relative);
  Future<File> yaml(
    Map<String, Object?> values, {
    String name = 'config/server.yaml',
  }) async {
    final file = File(path(name));
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(values));
    return file;
  }

  Map<String, Object?> keys([String id = 'fixture']) => {
    id: {'label': 'Fixture', 'privateKeyHex': privateKey},
  };
  Future<ServerOptions> load(
    File file, [
    Map<String, String> overrides = const {},
  ]) => loader.load({
    'XLOG_DATA_DIR': path('data'),
    ...overrides,
  }, configPath: file.path);
  TypeMatcher<ServerConfigurationException> fieldError(String field) =>
      isA<ServerConfigurationException>().having(
        (error) => error.field,
        'field',
        field,
      );

  test(
    'plain YAML loads all fields, inline keys, and resource limits',
    () async {
      final file = await yaml({});
      await file.writeAsString('''
host: localhost
port: 8099
dataDirectory: ../private/data
webRoot: ../public
allowedOrigins:
  - https://client.example
keys:
  fixture:
    label: Test fixture
    privateKeyHex: "$privateKey"
limits:
  maxUploadBytes: 123
  maxOutputBytes: 456
  maxConcurrentJobs: 1
  maxQueuedJobs: 0
  maxRetainedJobs: 1
  jobTtlSeconds: 17
  uploadTimeoutSeconds: 19
''');
      final result = await loader.load({}, configPath: file.path);
      final config = result.config;
      expect(result.host, 'localhost');
      expect(result.port, 8099);
      expect(config.dataDirectory.path, path('private/data'));
      expect(config.webRoot!.path, path('public'));
      expect(config.allowedOrigins, {'https://client.example'});
      expect(config.keys['fixture']!.privateKeyHex, privateKey);
      expect(config.maxUploadBytes, 123);
      expect(config.maxOutputBytes, 456);
      expect(config.maxConcurrentJobs, 1);
      expect(config.maxQueuedJobs, 0);
      expect(config.maxRetainedJobs, 1);
      expect(config.jobTtl, const Duration(seconds: 17));
      expect(config.uploadTimeout, const Duration(seconds: 19));
      expect(() => config.keys.clear(), throwsUnsupportedError);
      expect(() => config.allowedOrigins.clear(), throwsUnsupportedError);
    },
  );

  test(
    'environment overrides YAML and retains cwd-relative path semantics',
    () async {
      final file = await yaml({
        'host': 'yaml-host',
        'port': 9999,
        'dataDirectory': 'yaml-data',
        'webRoot': 'yaml-web',
        'allowedOrigins': ['https://yaml.example'],
        'limits': {
          'maxUploadBytes': 12,
          'maxOutputBytes': 13,
          'maxConcurrentJobs': 1,
          'maxQueuedJobs': 0,
          'maxRetainedJobs': 2,
          'jobTtlSeconds': 14,
          'uploadTimeoutSeconds': 15,
        },
      });
      final result = await load(file, {
        'HOST': 'env-host',
        'PORT': '0',
        'XLOG_DATA_DIR': 'relative-data',
        'XLOG_WEB_ROOT': 'relative-web',
        'XLOG_ALLOWED_ORIGINS': ' https://env.example, ',
        'XLOG_MAX_UPLOAD_BYTES': '21',
        'XLOG_MAX_OUTPUT_BYTES': '22',
        'XLOG_CONCURRENCY': '2',
        'XLOG_MAX_QUEUED': '1',
        'XLOG_MAX_JOBS': '3',
        'XLOG_JOB_TTL_SECONDS': '23',
        'XLOG_UPLOAD_TIMEOUT_SECONDS': '24',
      });
      expect(result.host, 'env-host');
      expect(result.port, 0);
      final config = result.config;
      expect(config.dataDirectory.path, 'relative-data');
      expect(config.webRoot!.path, 'relative-web');
      expect(config.allowedOrigins, {'https://env.example'});
      expect(config.maxUploadBytes, 21);
      expect(config.maxOutputBytes, 22);
      expect(config.maxConcurrentJobs, 2);
      expect(config.maxQueuedJobs, 1);
      expect(config.maxRetainedJobs, 3);
      expect(config.jobTtl.inSeconds, 23);
      expect(config.uploadTimeout.inSeconds, 24);
    },
  );

  test(
    'explicit config path takes precedence over the config environment',
    () async {
      final file = await yaml({'port': 1234});
      expect(
        (await load(file, {'XLOG_CONFIG_FILE': path('missing.yaml')})).port,
        1234,
      );
      final environment = {
        'XLOG_CONFIG_FILE': file.path,
        'XLOG_DATA_DIR': path('data'),
      };
      expect((await loader.load(environment)).port, 1234);
    },
  );

  test('YAML key-file paths are relative to the configuration file', () async {
    final file = await yaml({'keysFile': 'keys.json'});
    await File(
      p.join(file.parent.path, 'keys.json'),
    ).writeAsString(jsonEncode(keys()));
    expect((await load(file)).config.keys.keys, ['fixture']);
  });

  test('environment key file replaces inline YAML keys', () async {
    final file = await yaml({'keys': keys('yaml')});
    final envKeys = File(path('env-keys.json'));
    await envKeys.writeAsString(jsonEncode(keys('environment')));
    final relative = p.relative(envKeys.path, from: Directory.current.path);
    expect((await load(file, {'XLOG_KEYS_FILE': relative})).config.keys.keys, [
      'environment',
    ]);
  });

  test('keys and keysFile cannot be specified together', () async {
    final file = await yaml({'keys': keys(), 'keysFile': 'keys.json'});
    await expectLater(load(file), throwsA(fieldError('keys')));
  });

  test('empty web-root environment disables YAML static hosting', () async {
    final file = await yaml({'webRoot': '../public'});
    expect((await load(file, {'XLOG_WEB_ROOT': ''})).config.webRoot, isNull);
  });

  test('missing fields retain defaults including upload timeout', () async {
    final file = await yaml({});
    final result = await load(file);
    expect(result.host, '127.0.0.1');
    expect(result.port, 18781);
    expect(result.config.maxUploadBytes, 256 * 1024 * 1024);
    expect(result.config.uploadTimeout, const Duration(minutes: 10));
    expect(result.config.keys, isEmpty);
  });

  for (final document in ['[]', 'null', 'not-a-mapping']) {
    test('rejects a nonmapping YAML document: $document', () async {
      final file = await yaml({});
      await file.writeAsString(document);
      await expectLater(load(file), throwsA(fieldError('configuration')));
    });
  }

  for (final (values, field) in <(Map<String, Object?>, String)>[
    ({'unknown': true}, 'configuration'),
    (
      {
        'limits': {'typo': 1},
      },
      'limits',
    ),
    ({'host': 12}, 'host'),
    ({'port': '18781'}, 'port'),
    ({'port': 65536}, 'port'),
    ({'dataDirectory': []}, 'dataDirectory'),
    ({'allowedOrigins': 'https://example.test'}, 'allowedOrigins'),
    (
      {
        'allowedOrigins': [12],
      },
      'allowedOrigins',
    ),
    ({'keys': []}, 'keys'),
    (
      {
        'keys': {
          'a': {'privateKeyHex': 123},
        },
      },
      'keys.privateKeyHex',
    ),
    (
      {
        'keys': {
          'a': {'privateKeyHex': 'bad-private-key'},
        },
      },
      'keys.privateKeyHex',
    ),
    (
      {
        'keys': {
          'a': {'privateKeyHex': 'secret', 'extra': true},
        },
      },
      'keys',
    ),
    (
      {
        'limits': {'maxUploadBytes': '123'},
      },
      'limits.maxUploadBytes',
    ),
    (
      {
        'limits': {'maxUploadBytes': 0},
      },
      'limits.maxUploadBytes',
    ),
    (
      {
        'limits': {'maxOutputBytes': -1},
      },
      'limits.maxOutputBytes',
    ),
    (
      {
        'limits': {'maxConcurrentJobs': 0},
      },
      'limits.maxConcurrentJobs',
    ),
    (
      {
        'limits': {'maxQueuedJobs': -1},
      },
      'limits.maxQueuedJobs',
    ),
    (
      {
        'limits': {'maxRetainedJobs': 1},
      },
      'limits.maxRetainedJobs',
    ),
    (
      {
        'limits': {'jobTtlSeconds': 0},
      },
      'limits.jobTtlSeconds',
    ),
    (
      {
        'limits': {'uploadTimeoutSeconds': 0},
      },
      'limits.uploadTimeoutSeconds',
    ),
  ]) {
    test('rejects invalid YAML field $field (${values.keys.first})', () async {
      final file = await yaml(values);
      await expectLater(load(file), throwsA(fieldError(field)));
    });
  }

  test(
    'invalid environment diagnostics identify the field without its value',
    () async {
      const secret = 'do-not-print-this-private-value';
      final file = await yaml({});
      await expectLater(
        load(file, {'XLOG_UPLOAD_TIMEOUT_SECONDS': secret}),
        throwsA(
          fieldError('XLOG_UPLOAD_TIMEOUT_SECONDS').having(
            (error) => error.toString(),
            'diagnostic',
            isNot(contains(secret)),
          ),
        ),
      );
    },
  );

  test('malformed YAML diagnostics never include source excerpts', () async {
    const secret = 'do-not-print-this-private-value';
    final file = await yaml({});
    await file.writeAsString('keysFile: "$secret"\nkeys: [invalid');
    await expectLater(
      load(file),
      throwsA(
        fieldError('configFile').having(
          (error) => error.toString(),
          'diagnostic',
          isNot(contains(secret)),
        ),
      ),
    );
  });

  test(
    'missing configuration and key files produce safe field diagnostics',
    () async {
      await expectLater(
        loader.load({}, configPath: path('missing-secret.yaml')),
        throwsA(
          fieldError('configFile').having(
            (error) => error.toString(),
            'diagnostic',
            isNot(contains('missing-secret')),
          ),
        ),
      );
      final file = await yaml({'keysFile': 'missing-secret.json'});
      await expectLater(
        load(file),
        throwsA(
          fieldError('keysFile').having(
            (error) => error.toString(),
            'diagnostic',
            isNot(contains('missing-secret')),
          ),
        ),
      );
    },
  );

  test(
    'configuration file cannot be served by the final public root',
    () async {
      final file = await yaml({
        'keys': {
          'fixture': {'privateKeyHex': privateKey},
        },
      }, name: 'public/server.yaml');
      await expectLater(
        load(file, {'XLOG_WEB_ROOT': file.parent.path}),
        throwsA(fieldError('configFile')),
      );
    },
  );

  test(
    'configuration path and public-root aliases cannot expose the file',
    () async {
      final file = await yaml({}, name: 'public/server.yaml');
      final fileAlias = Link(path('config-alias.yaml'));
      final rootAlias = Link(path('public-alias'));
      await fileAlias.create(file.path);
      await rootAlias.create(file.parent.path);
      for (final (config, web) in [
        (fileAlias.path, file.parent.path),
        (file.path, rootAlias.path),
      ]) {
        await expectLater(
          loader.load({
            'XLOG_DATA_DIR': path('data'),
            'XLOG_WEB_ROOT': web,
          }, configPath: config),
          throwsA(fieldError('configFile')),
        );
      }
    },
  );

  test(
    'YAML key-file aliases are checked against the final public root',
    () async {
      final public = await Directory(path('public')).create();
      final key = File(p.join(public.path, 'keys.json'));
      await key.writeAsString(jsonEncode(keys()));
      final alias = Link(path('keys-alias.json'));
      await alias.create(key.path);
      final file = await yaml({'keysFile': '../keys-alias.json'});
      await expectLater(
        load(file, {'XLOG_WEB_ROOT': public.path}),
        throwsA(fieldError('keysFile')),
      );
    },
  );

  test('loader reuses directory separation and realpath checks', () async {
    final public = await Directory(path('public')).create();
    final alias = Link(path('data-alias'));
    await alias.create(public.path);
    final file = await yaml({
      'dataDirectory': '../data-alias',
      'webRoot': '../public',
    });
    await expectLater(
      loader.load({}, configPath: file.path),
      throwsA(fieldError('dataDirectory')),
    );
  });

  test(
    'validation failure removes an automatically allocated data directory',
    () async {
      Future<Set<String>> workspaces() async => {
        await for (final entry in Directory.systemTemp.list())
          if (p.basename(entry.path).startsWith('xlog-server-')) entry.path,
      };
      final before = await workspaces();
      await expectLater(
        loader.load({'XLOG_WEB_ROOT': Directory.systemTemp.path}),
        throwsA(fieldError('dataDirectory')),
      );
      expect((await workspaces()).difference(before), isEmpty);
    },
  );
}
