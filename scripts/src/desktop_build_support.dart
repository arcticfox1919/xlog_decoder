import 'dart:io';

class AppVersion {
  const AppVersion(this.full, this.name, this.buildNumber);

  final String full;
  final String name;
  final String buildNumber;

  String archiveNameFor(String platform) => 'Xlog-Decoder-$full-$platform.zip';
}

Future<AppVersion> readVersion(Directory project) async {
  final pubspec = await File('${project.path}/pubspec.yaml').readAsString();
  final match = RegExp(
    r'^version:\s*(\S+)',
    multiLine: true,
  ).firstMatch(pubspec);
  final version = (match?.group(1) ?? '')
      .replaceAll("'", '')
      .replaceAll('"', '');
  final valid = RegExp(r'^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$');
  if (!valid.hasMatch(version)) {
    throw const FormatException(
      'pubspec.yaml does not contain a valid version, such as 1.0.0.',
    );
  }
  return AppVersion(version, version, '1');
}

String findFlutter(Directory project) {
  final override = Platform.environment['FLUTTER_BIN'];
  if (override != null && override.isNotEmpty) {
    if (!File(override).existsSync()) {
      throw StateError(
        'FLUTTER_BIN points to a file that does not exist: $override',
      );
    }
    return File(override).absolute.path;
  }

  // When running with Flutter's bundled Dart, the SDK root is four levels up.
  final sdkBin = File(Platform.resolvedExecutable).parent.parent.parent.parent;
  final flutterRoot = Platform.environment['FLUTTER_ROOT'];
  final executable = Platform.isWindows ? 'flutter.bat' : 'flutter';
  final separator = Platform.isWindows ? ';' : ':';
  final candidates = [
    '${project.path}/.fvm/flutter_sdk/bin/$executable',
    '${sdkBin.path}/$executable',
    if (flutterRoot != null) '$flutterRoot/bin/$executable',
    for (final directory in (Platform.environment['PATH'] ?? '').split(
      separator,
    ))
      if (directory.isNotEmpty) '$directory/$executable',
  ];
  for (final candidate in candidates) {
    if (File(candidate).existsSync()) return File(candidate).absolute.path;
  }
  throw StateError(
    'Flutter executable not found. Set FLUTTER_BIN to its path and try again.',
  );
}

Future<void> runCommand(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
}) async {
  final process = await Process.start(
    executable,
    arguments,
    workingDirectory: workingDirectory,
    mode: ProcessStartMode.inheritStdio,
    runInShell:
        Platform.isWindows &&
        (executable.endsWith('.bat') || executable.endsWith('.cmd')),
  );
  final code = await process.exitCode;
  if (code != 0) {
    throw ProcessException(executable, arguments, 'Command failed', code);
  }
}

Future<String> commandOutput(String executable, List<String> arguments) async {
  final result = await Process.run(executable, arguments);
  if (result.exitCode != 0) {
    throw ProcessException(
      executable,
      arguments,
      result.stderr.toString(),
      result.exitCode,
    );
  }
  return result.stdout.toString().trim();
}
