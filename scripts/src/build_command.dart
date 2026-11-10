import 'dart:io';

import 'process_support.dart';
import 'web_options.dart';

class BuildCommand {
  const BuildCommand(this.processes);
  final ProcessSupport processes;

  Future<void> run(WebOptions options) async {
    // Build tools never receive the backend's runtime configuration or keys.
    final environment = processes.environment();
    if (options.command != WebCommand.buildServer) {
      await processes.dependencies('xlog_web', environment);
      await processes.command('xlog_web', [
        'run',
        'jaspr_cli:jaspr',
        'build',
        if (options.apiUrl != null)
          '--dart-define-client=XLOG_API_BASE_URL=${options.apiUrl.toString().replaceAll('=', '%3D')}',
      ], environment);
      stdout.writeln(
        'Web build complete: ${processes.root.path}/packages/xlog_web/build/jaspr/',
      );
    }
    if (options.command != WebCommand.build) {
      await processes.dependencies('xlog_server', environment);
      final directory = Directory('${processes.root.path}/build/server');
      await directory.create(recursive: true);
      final output =
          '${directory.path}/xlog_server${Platform.isWindows ? '.exe' : ''}';
      await processes.command('xlog_server', [
        'compile',
        'exe',
        'bin/server.dart',
        '-o',
        output,
      ], environment);
      stdout.writeln('Server build complete: $output');
    }
  }
}
