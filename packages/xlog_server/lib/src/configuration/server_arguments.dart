/// Command-line selection of a configuration file; values remain in the loader.
class ServerArguments {
  const ServerArguments({this.configPath, this.help = false});

  final String? configPath;
  final bool help;

  factory ServerArguments.parse(List<String> arguments) {
    if (arguments.contains('--help') || arguments.contains('-h')) {
      return const ServerArguments(help: true);
    }
    String? path;
    for (var index = 0; index < arguments.length; index++) {
      final argument = arguments[index];
      if (argument != '--config' && !argument.startsWith('--config=')) {
        throw const FormatException('Unknown option. Use --help for usage.');
      }
      if (path != null) {
        throw const FormatException('Specify --config only once.');
      }
      if (argument.startsWith('--config=')) {
        path = argument.substring('--config='.length);
      } else if (index + 1 < arguments.length &&
          !arguments[index + 1].startsWith('-')) {
        path = arguments[++index];
      } else {
        throw const FormatException('--config requires a YAML file path.');
      }
      if (path.trim().isEmpty) {
        throw const FormatException('--config requires a YAML file path.');
      }
    }
    return ServerArguments(configPath: path);
  }
}
