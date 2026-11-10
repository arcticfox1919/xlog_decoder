import 'dart:io';

import 'src/web_runner.dart';

const usage = '''
Usage (from the repository root):
  dart scripts/web.dart                     Start the same-origin gateway and development services
  dart scripts/web.dart dev --no-open       Start development services without opening the browser
  dart scripts/web.dart dev --web-port 18782 --server-port 18783
  dart scripts/web.dart --config /path/server.yaml
  dart scripts/web.dart build               Build the Web static files
  dart scripts/web.dart build --api-url https://api.example.com/
  dart scripts/web.dart build-server        Compile a native standalone backend
  dart scripts/web.dart build-all           Build Web, then the native backend

Use a standalone Dart SDK 3.11 or newer (below 4.0).
Missing dependencies are downloaded automatically.
Development entry: http://localhost:18780/ (API and Web share this origin).
Backend: 127.0.0.1:18781; Jaspr uses a private random port. Press Ctrl+C to stop.
The backend reads XLOG_* environment variables. This script manages HOST, PORT,
and XLOG_WEB_ROOT in development mode.
Web output: packages/xlog_web/build/jaspr/.
Native backend output: build/server/xlog_server (xlog_server.exe on Windows).
''';

Future<void> main(List<String> arguments) async {
  if (arguments.contains('--help') || arguments.contains('-h')) {
    stdout.write(usage);
    return;
  }
  try {
    final options = WebOptions.parse(arguments);
    final root = File.fromUri(Platform.script).parent.parent;
    await WebRunner(root).run(options);
  } on FormatException catch (error) {
    stderr.writeln('${error.message}\n\n$usage');
    exitCode = 64;
  } catch (error) {
    stderr.writeln('Failed: $error');
    exitCode = 1;
  }
}
