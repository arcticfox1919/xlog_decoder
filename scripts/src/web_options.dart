enum WebCommand { dev, build, buildServer, buildAll }

/// Options shared by the command entry point and the process runner.
class WebOptions {
  const WebOptions({
    this.command = WebCommand.dev,
    this.openBrowser = true,
    this.webPort = 18780,
    this.serverPort = 18781,
    this.apiUrl,
    this.serverConfigPath,
  });

  final WebCommand command;
  bool get build => command == WebCommand.build;
  final bool openBrowser;
  final int webPort;
  final int serverPort;
  final Uri? apiUrl;
  final String? serverConfigPath;

  factory WebOptions.parse(List<String> arguments) {
    final args = arguments.toList();
    final command = args.isNotEmpty && !args.first.startsWith('-')
        ? args.removeAt(0)
        : 'dev';
    if (!['dev', 'build', 'build-server', 'build-all'].contains(command)) {
      throw FormatException('Unknown command: $command');
    }
    final values = <String, String>{};
    var open = true;
    for (var i = 0; i < args.length; i++) {
      final parts = args[i].split('=');
      final flag = parts.first;
      if (flag == '--no-open' && parts.length == 1 && command == 'dev') {
        open = false;
        continue;
      }
      final allowed = command == 'dev'
          ? const ['--web-port', '--server-port', '--config']
          : command == 'build-server'
          ? const <String>[]
          : const ['--api-url'];
      if (!allowed.contains(flag)) {
        throw FormatException('Unknown option: ${args[i]}');
      }
      final String value;
      if (parts.length > 1) {
        value = args[i].substring(flag.length + 1);
      } else if (i + 1 < args.length && !args[i + 1].startsWith('-')) {
        value = args[++i];
      } else {
        throw FormatException('$flag requires a value.');
      }
      if (values.containsKey(flag)) {
        throw FormatException('Duplicate option: $flag');
      }
      values[flag] = value;
    }
    int port(String flag, int fallback) {
      final value = values[flag];
      if (value == null) return fallback;
      final parsed = int.tryParse(value);
      if (parsed == null || parsed < 1 || parsed > 65535) {
        throw FormatException('$flag must be a port between 1 and 65535.');
      }
      return parsed;
    }

    final webPort = port('--web-port', 18780);
    final serverPort = port('--server-port', 18781);
    if (command == 'dev' && webPort == serverPort) {
      throw const FormatException(
        'Frontend and backend ports must be different.',
      );
    }
    if (values['--config']?.trim().isEmpty ?? false) {
      throw const FormatException('--config requires a YAML file path.');
    }
    Uri? apiUrl;
    if (values.containsKey('--api-url')) {
      apiUrl = Uri.tryParse(values['--api-url']!);
      if (apiUrl == null ||
          !['http', 'https'].contains(apiUrl.scheme) ||
          apiUrl.host.isEmpty ||
          apiUrl.userInfo.isNotEmpty ||
          apiUrl.hasQuery ||
          apiUrl.hasFragment) {
        throw const FormatException(
          '--api-url must be an HTTP(S) URL without credentials, query parameters, or fragments.',
        );
      }
      if (!apiUrl.path.endsWith('/')) {
        apiUrl = apiUrl.replace(path: '${apiUrl.path}/');
      }
    }
    return WebOptions(
      command: switch (command) {
        'dev' => WebCommand.dev,
        'build' => WebCommand.build,
        'build-server' => WebCommand.buildServer,
        _ => WebCommand.buildAll,
      },
      openBrowser: open,
      webPort: webPort,
      serverPort: serverPort,
      apiUrl: apiUrl,
      serverConfigPath: values['--config'],
    );
  }
}
