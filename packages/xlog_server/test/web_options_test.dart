import 'package:test/test.dart';

import '../../../scripts/src/web_options.dart';

void main() {
  group('development options', () {
    test('accepts a YAML configuration file without changing ports', () {
      for (final arguments in [
        ['--config', 'private/server.yaml'],
        ['dev', '--config=private/server.yaml'],
      ]) {
        final options = WebOptions.parse(arguments);
        expect(options.serverConfigPath, 'private/server.yaml');
        expect(options.serverPort, 18781);
      }
      for (final arguments in [
        ['--config'],
        ['--config='],
        ['--config=a.yaml', '--config=b.yaml'],
        ['build', '--config=a.yaml'],
      ]) {
        expect(() => WebOptions.parse(arguments), throwsFormatException);
      }
    });
    test('defaults to dev with browser and distinct local ports', () {
      for (final arguments in <List<String>>[
        [],
        ['dev'],
      ]) {
        final options = WebOptions.parse(arguments);
        expect(options.build, isFalse);
        expect(options.openBrowser, isTrue);
        expect(options.webPort, 18780);
        expect(options.serverPort, 18781);
        expect(options.apiUrl, isNull);
      }
    });

    test('accepts implicit dev, both value syntaxes and no-open', () {
      final arguments = [
        '--no-open',
        '--web-port=9000',
        '--server-port',
        '9001',
      ];
      final options = WebOptions.parse(arguments);
      expect(options.build, isFalse);
      expect(options.openBrowser, isFalse);
      expect(options.webPort, 9000);
      expect(options.serverPort, 9001);
      expect(arguments, [
        '--no-open',
        '--web-port=9000',
        '--server-port',
        '9001',
      ]);
    });

    test('accepts both inclusive port boundaries', () {
      final options = WebOptions.parse([
        'dev',
        '--web-port',
        '1',
        '--server-port=65535',
      ]);
      expect(options.webPort, 1);
      expect(options.serverPort, 65535);
    });

    test('rejects equal ports, including conflicts with a default', () {
      for (final arguments in [
        ['--web-port=18781'],
        ['--server-port=18780'],
        ['dev', '--web-port=9000', '--server-port=9000'],
      ]) {
        expect(() => WebOptions.parse(arguments), throwsFormatException);
      }
    });

    test('rejects nonnumeric and out-of-range port values', () {
      for (final flag in ['--web-port', '--server-port']) {
        for (final value in ['', '0', '-1', '65536', '1.5', 'localhost']) {
          expect(
            () => WebOptions.parse(['$flag=$value']),
            throwsFormatException,
            reason: '$flag must reject "$value"',
          );
        }
      }
    });
  });

  group('command and argument validation', () {
    test('build defaults to same-origin API', () {
      final options = WebOptions.parse(['build']);
      expect(options.build, isTrue);
      expect(options.apiUrl, isNull);
    });

    test(
      'rejects unknown commands, unknown flags and positional arguments',
      () {
        for (final arguments in [
          ['serve'],
          ['--unknown'],
          ['dev', 'extra'],
          ['build', 'extra'],
          ['dev', '--no-open=false'],
        ]) {
          expect(() => WebOptions.parse(arguments), throwsFormatException);
        }
      },
    );

    test('rejects flags belonging to the other mode', () {
      for (final arguments in [
        ['dev', '--api-url=https://example.com'],
        ['build', '--web-port=9000'],
        ['build', '--server-port=9001'],
        ['build', '--no-open'],
      ]) {
        expect(() => WebOptions.parse(arguments), throwsFormatException);
      }
    });

    test('rejects missing values and does not consume the next flag', () {
      for (final arguments in [
        ['dev', '--web-port'],
        ['dev', '--server-port'],
        ['dev', '--web-port', '--no-open'],
        ['dev', '--server-port', '--web-port=9000'],
        ['build', '--api-url'],
        ['build', '--api-url', '--no-open'],
      ]) {
        expect(() => WebOptions.parse(arguments), throwsFormatException);
      }
    });

    test('rejects duplicate valued flags across value syntaxes', () {
      for (final arguments in [
        ['--web-port=9000', '--web-port', '9001'],
        ['dev', '--server-port', '9000', '--server-port=9001'],
        [
          'build',
          '--api-url=https://example.com',
          '--api-url',
          'https://other.example.com',
        ],
      ]) {
        expect(() => WebOptions.parse(arguments), throwsFormatException);
      }
    });
  });

  test('accepts native server and combined build commands', () {
    expect(WebOptions.parse(['build-server']).command, WebCommand.buildServer);
    final all = WebOptions.parse([
      'build-all',
      '--api-url=https://example.com',
    ]);
    expect(all.command, WebCommand.buildAll);
    expect(all.apiUrl.toString(), 'https://example.com/');
    for (final command in ['build-server', 'build-all']) {
      for (final flag in ['--config=a.yaml', '--web-port=9000', '--no-open']) {
        expect(() => WebOptions.parse([command, flag]), throwsFormatException);
      }
    }
    expect(
      () => WebOptions.parse(['build-server', '--api-url=https://example.com']),
      throwsFormatException,
    );
  });

  group('build API URL', () {
    test('normalizes HTTP(S) roots and path prefixes to a trailing slash', () {
      for (final entry in {
        'https://example.com': 'https://example.com/',
        'http://localhost:18781': 'http://localhost:18781/',
        'https://example.com/decoder': 'https://example.com/decoder/',
        'https://example.com/decoder/': 'https://example.com/decoder/',
        'http://[::1]:18781/api': 'http://[::1]:18781/api/',
      }.entries) {
        final options = WebOptions.parse(['build', '--api-url', entry.key]);
        expect(options.build, isTrue);
        expect(options.apiUrl.toString(), entry.value);
      }
    });

    test('accepts inline API URL syntax', () {
      final options = WebOptions.parse([
        'build',
        '--api-url=https://example.com/base',
      ]);
      expect(options.apiUrl, Uri.parse('https://example.com/base/'));
    });

    test('rejects relative, empty, malformed and non-HTTP URLs', () {
      for (final url in [
        '',
        '/api',
        '//example.com/api',
        'example.com/api',
        'ftp://example.com/api',
        'file:///tmp/api',
        'https:///api',
        'http://[invalid',
      ]) {
        expect(
          () => WebOptions.parse(['build', '--api-url=$url']),
          throwsFormatException,
          reason: 'API URL must reject "$url"',
        );
      }
    });

    test('rejects credentials, queries and fragments including empty ones', () {
      for (final url in [
        'https://user:secret@example.com',
        'https://user@example.com',
        'https://example.com/api?token=secret',
        'https://example.com/api?',
        'https://example.com/api#section',
        'https://example.com/api#',
      ]) {
        expect(
          () => WebOptions.parse(['build', '--api-url=$url']),
          throwsFormatException,
          reason: 'API URL must reject "$url"',
        );
      }
    });
  });
}
