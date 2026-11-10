import 'package:test/test.dart';
import 'package:xlog_server/src/configuration/server_arguments.dart';

void main() {
  test('accepts defaults, help, separate and inline config paths', () {
    expect(ServerArguments.parse([]).configPath, isNull);
    expect(ServerArguments.parse(['--help']).help, isTrue);
    expect(ServerArguments.parse(['-h']).help, isTrue);
    expect(
      ServerArguments.parse(['--config', 'server.yaml']).configPath,
      'server.yaml',
    );
    expect(
      ServerArguments.parse(['--config=private config.yml']).configPath,
      'private config.yml',
    );
  });

  test('rejects missing, empty, duplicate and unknown arguments', () {
    for (final arguments in [
      ['--config'],
      ['--config='],
      ['--config=  '],
      ['--config', '--other'],
      ['--config=a.yaml', '--config=b.yaml'],
      ['--config', 'a.yaml', 'b.yaml'],
      ['--unknown=secret-value'],
    ]) {
      expect(
        () => ServerArguments.parse(arguments),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            isNot(contains('secret-value')),
          ),
        ),
      );
    }
  });
}
