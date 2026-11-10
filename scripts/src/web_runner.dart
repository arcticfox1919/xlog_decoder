import 'dart:io';

import 'build_command.dart';
import 'development_command.dart';
import 'process_support.dart';
import 'web_options.dart';

export 'web_options.dart';

/// Selects a command and guarantees cleanup for every exit path.
class WebRunner {
  WebRunner(this.root);
  final Directory root;

  Future<void> run(WebOptions options) async {
    final version = Platform.version.split(' ').first.split('.');
    final major = int.parse(version[0]);
    final minor = int.parse(version[1]);
    if (major != 3 || minor < 11) {
      throw StateError(
        'Web and server commands require Dart >=3.11.0 <4.0.0. '
        'Current SDK: ${Platform.version.split(' ').first}. '
        'Run this script with your standalone Dart SDK.',
      );
    }
    final processes = ProcessSupport(root)..watchSignals();
    try {
      if (options.command == WebCommand.dev) {
        await DevelopmentCommand(processes).run(options);
      } else {
        await BuildCommand(processes).run(options);
      }
    } on ScriptInterrupted {
      // An interruption during startup is a normal exit.
    } finally {
      await processes.dispose();
    }
  }
}
