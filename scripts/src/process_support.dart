import 'dart:async';
import 'dart:io';

/// SDK selection, child process ownership, readiness and signal cleanup.
class ProcessSupport {
  ProcessSupport(this.root);
  final Directory root;
  final _children = <Process>{};
  final _signals = <StreamSubscription<ProcessSignal>>[];
  final _stopped = Completer<void>();
  Future<void>? _stopping;

  Future<void> get stopped => _stopped.future;
  bool get stopping => _stopping != null;

  void watchSignals() {
    for (final signal in [
      ProcessSignal.sigint,
      if (!Platform.isWindows) ProcessSignal.sigterm,
    ]) {
      _signals.add(signal.watch().listen((_) => unawaited(close())));
    }
  }

  Future<void> dispose() async {
    await close();
    for (final signal in _signals) {
      await signal.cancel();
    }
  }

  Map<String, String> environment({bool backend = false}) {
    final env = Map<String, String>.from(Platform.environment);
    final sdkBin = File(Platform.resolvedExecutable).parent.path;
    final pathKey = env.keys.firstWhere(
      (key) => key.toUpperCase() == 'PATH',
      orElse: () => 'PATH',
    );
    env[pathKey] =
        '$sdkBin${Platform.isWindows ? ';' : ':'}${env[pathKey] ?? ''}';
    // No server configuration is sent to the frontend toolchain.
    if (!backend) {
      env.removeWhere((key, _) => key.toUpperCase().startsWith('XLOG_'));
    }
    return env;
  }

  Future<Process> start(
    String package,
    List<String> args,
    Map<String, String> env,
  ) async {
    if (_stopping != null) throw const ScriptInterrupted();
    final process = await Process.start(
      Platform.resolvedExecutable,
      args,
      workingDirectory: '${root.path}/packages/$package',
      environment: env,
      includeParentEnvironment: false,
    );
    _children.add(process);
    process.stdout.listen(stdout.add);
    process.stderr.listen(stderr.add);
    unawaited(process.exitCode.then((_) => _children.remove(process)));
    if (_stopping != null) {
      await _terminate(process);
      throw const ScriptInterrupted();
    }
    return process;
  }

  Future<void> command(
    String package,
    List<String> args,
    Map<String, String> env,
  ) async {
    final process = await start(package, args, env);
    final code = await process.exitCode;
    if (_stopping != null) throw const ScriptInterrupted();
    if (code != 0) {
      throw StateError(
        '$package: dart ${args.join(' ')} failed (exit code $code).',
      );
    }
  }

  Future<void> dependencies(String package, Map<String, String> env) async {
    // Reuse compatible locked versions and the cache when possible. Web build
    // tools have SDK-specific releases, so allow Pub to adapt to this SDK.
    final cached = await start(package, ['pub', 'get', '--offline'], env);
    final code = await cached.exitCode;
    if (_stopping != null) throw const ScriptInterrupted();
    if (code != 0) {
      stdout.writeln('$package: Downloading missing dependencies...');
      await command(package, ['pub', 'get'], env);
    }
  }

  Future<void> ready(Uri url, Process process) async {
    int? exited;
    unawaited(process.exitCode.then((code) => exited = code));
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 1);
    final deadline = DateTime.now().add(const Duration(minutes: 5));
    try {
      while (DateTime.now().isBefore(deadline)) {
        if (_stopping != null) throw const ScriptInterrupted();
        if (exited != null) {
          throw StateError('Failed to start $url (exit code $exited).');
        }
        try {
          final request = await client.getUrl(url);
          final response = await request.close().timeout(
            const Duration(seconds: 2),
          );
          final status = response.statusCode;
          await response.drain<void>().timeout(const Duration(seconds: 2));
          if (status == HttpStatus.ok) return;
        } on IOException {
          // The listening socket may precede the first successful Web build.
        } on TimeoutException {
          // Retry while the dev server is compiling.
        }
        await Future.any([
          Future<void>.delayed(const Duration(milliseconds: 300)),
          _stopped.future,
        ]);
      }
      throw StateError('Timed out waiting for $url. Check the logs above.');
    } finally {
      client.close(force: true);
    }
  }

  Future<void> openBrowser(Uri url) async {
    try {
      final command = Platform.isMacOS
          ? 'open'
          : Platform.isWindows
          ? 'rundll32'
          : 'xdg-open';
      // The browser lives independently of the dev services and has no pipes
      // that could keep this script running after Ctrl+C.
      await Process.start(
        command,
        [if (Platform.isWindows) 'url.dll,FileProtocolHandler', '$url'],
        environment: environment(),
        includeParentEnvironment: false,
        mode: ProcessStartMode.detached,
      );
      return;
    } on ProcessException {
      // Headless environments may not have a browser opener.
    }
    stdout.writeln('Could not open the browser. Visit $url manually.');
  }

  Future<void> close() => _stopping ??= _stopChildren();

  Future<void> _stopChildren() async {
    _stopped.complete();
    final children = _children.toList().reversed.toList();
    await Future.wait(children.map(_terminate));
  }

  Future<void> _terminate(Process child) async {
    if (Platform.isWindows) {
      // Process.kill on Windows cannot deliver SIGINT to Jaspr's cleanup code.
      // Stop the owned process tree, including build_runner and compilers.
      await Process.run('taskkill', ['/PID', '${child.pid}', '/T', '/F']);
    } else {
      child.kill(ProcessSignal.sigint);
    }
    try {
      await child.exitCode.timeout(const Duration(seconds: 10));
    } on TimeoutException {
      child.kill(ProcessSignal.sigkill);
      await child.exitCode;
    }
  }
}

class ScriptInterrupted implements Exception {
  const ScriptInterrupted();
}
