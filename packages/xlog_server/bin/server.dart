import 'dart:io';
import 'package:logging/logging.dart';
import 'package:xlog_server/src/diagnostics/server_logging.dart';

import 'package:xlog_server/src/configuration/server_arguments.dart';
import 'package:xlog_server/xlog_server.dart';

const usage = '''
Usage: dart run bin/server.dart [--config /path/server.yaml]

Configuration: environment variables > YAML file > defaults.
Use XLOG_CONFIG_FILE to select a YAML file without command-line options.
''';

Future<void> main(List<String> arguments) async {
  final ServerArguments args;
  try {
    args = ServerArguments.parse(arguments);
  } on FormatException catch (error) {
    stderr.writeln('${error.message}\n$usage');
    exitCode = 64;
    return;
  }
  if (args.help) {
    stdout.write(usage);
    return;
  }
  try {
    configureServerLogging(
      levelName: Platform.environment['XLOG_LOG_LEVEL'] ?? 'INFO',
    );
  } on FormatException catch (error) {
    stderr.writeln(error.message);
    exitCode = 64;
    return;
  }
  final log = Logger('xlog.server');
  try {
    final options = await const ServerEnvironment().load(
      Platform.environment,
      configPath: args.configPath,
    );
    final app = await XlogServer.bind(
      options.config,
      host: options.host,
      port: options.port,
    );
    for (final signal in [
      ProcessSignal.sigint,
      if (!Platform.isWindows) ProcessSignal.sigterm,
    ]) {
      signal.watch().listen((_) async {
        await app.close();
        await stdout.flush();
        await stderr.flush();
        exit(0);
      });
    }
  } on ServerConfigurationException catch (error) {
    log.severe({
      'event': 'server.configuration.failed',
      'message': error.message,
    });
    exitCode = 78;
  } catch (error, stack) {
    logFailure(log, Level.SEVERE, 'server.start.failed', error, stack);
    exitCode = 1;
  }
}
