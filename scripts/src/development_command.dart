import 'dart:async';
import 'dart:io';

import 'dev_gateway.dart';
import 'port_check.dart';
import 'process_support.dart';
import 'web_options.dart';

class DevelopmentCommand {
  const DevelopmentCommand(this.processes);
  final ProcessSupport processes;

  Future<void> run(WebOptions options) async {
    await checkAvailablePort(options.webPort);
    await checkAvailablePort(options.serverPort);
    final jasprPort = await findAvailablePort(
      excluding: {options.webPort, options.serverPort},
    );
    final webdevPort = await findAvailablePort(
      excluding: {options.webPort, options.serverPort, jasprPort},
    );
    final publicUrl = Uri.parse('http://localhost:${options.webPort}/');
    final apiUrl = Uri.parse('http://127.0.0.1:${options.serverPort}/');
    final jasprUrl = Uri.parse('http://127.0.0.1:$jasprPort/');
    final gateway = await DevGateway.bind(
      port: options.webPort,
      backend: apiUrl,
      frontend: jasprUrl,
      devtools: Uri.parse('http://127.0.0.1:$webdevPort/'),
    );
    try {
      final serverEnvironment = processes.environment(backend: true)
        ..['HOST'] = '127.0.0.1'
        ..['PORT'] = '${options.serverPort}'
        ..['XLOG_WEB_ROOT'] = '';
      final configPath =
          options.serverConfigPath ?? serverEnvironment['XLOG_CONFIG_FILE'];
      if (configPath != null) {
        serverEnvironment['XLOG_CONFIG_FILE'] = File(configPath).absolute.path;
      }
      final webEnvironment = processes.environment();
      await processes.dependencies('xlog_server', serverEnvironment);
      await processes.dependencies('xlog_web', webEnvironment);
      final server = await processes.start('xlog_server', [
        '--packages=.dart_tool/package_config.json',
        'bin/server.dart',
      ], serverEnvironment);
      await processes.ready(apiUrl.resolve('api/health'), server);
      final web = await processes.start('xlog_web', [
        'run',
        'jaspr_cli:jaspr',
        'serve',
        '--port',
        '$jasprPort',
        '--web-port',
        '$webdevPort',
      ], webEnvironment);
      stdout.writeln('Starting Web. The first build may take a few minutes...');
      await Future.any<void>([
        processes.ready(jasprUrl, web),
        server.exitCode.then((code) {
          if (processes.stopping) throw const ScriptInterrupted();
          throw StateError('Backend exited unexpectedly (exit code $code).');
        }),
      ]);
      stdout.writeln(
        '\nWeb: $publicUrl\nAPI: ${publicUrl.resolve('api/')}\nPress Ctrl+C to stop.',
      );
      if (options.openBrowser) await processes.openBrowser(publicUrl);
      await Future.any<void>([
        processes.stopped,
        for (final child in [server, web])
          child.exitCode.then((code) {
            if (!processes.stopping) {
              throw StateError(
                'Service exited unexpectedly (exit code $code).',
              );
            }
          }),
      ]);
    } finally {
      await gateway.close();
    }
  }
}
