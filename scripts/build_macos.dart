import 'dart:io';

import 'src/desktop_build_support.dart';

const appName = 'XlogDecoder.app';
const usage = '''
Usage: dart scripts/build_macos.dart

Build an arm64 macOS release and create a versioned ZIP archive.
The version is read from pubspec.yaml, and artifacts are saved to
build/macos/dist/.
Set FLUTTER_BIN to use a specific Flutter executable.
''';

Future<void> main(List<String> arguments) async {
  if (arguments.length == 1 && ['--help', '-h'].contains(arguments.single)) {
    stdout.write(usage);
    return;
  }
  if (arguments.isNotEmpty) {
    stderr.write(usage);
    exitCode = 64;
    return;
  }

  try {
    if (!Platform.isMacOS) {
      throw StateError('Run this script on macOS with Xcode installed.');
    }
    final project = File.fromUri(Platform.script).parent.parent;
    final version = await readVersion(project);
    final flutter = findFlutter(project);

    await buildRelease(project, flutter, version);
    final archive = await packageRelease(project, version);
    stdout.writeln('\nPackaging complete: ${archive.path}');
  } catch (error) {
    stderr.writeln('Packaging failed: $error');
    exitCode = 1;
  }
}

Future<void> buildRelease(
  Directory project,
  String flutter,
  AppVersion version,
) async {
  stdout.writeln('Building macOS arm64 release ${version.full}…');
  await runCommand(flutter, [
    'build',
    'macos',
    '--release',
    '--build-name',
    version.name,
    '--build-number',
    version.buildNumber,
  ], workingDirectory: project.path);
}

Future<File> packageRelease(Directory project, AppVersion version) async {
  final release = '${project.path}/build/macos/Build/Products/Release';
  final output = await Directory(
    '${project.path}/build/macos/dist',
  ).create(recursive: true);
  final staging = await output.createTemp('.package.');
  try {
    final app = Directory('${staging.path}/$appName');
    final archive = File(
      '${staging.path}/${version.archiveNameFor('macOS-arm64')}',
    );

    await runCommand('ditto', ['$release/xlog_decoder.app', app.path]);
    await verifyVersion(app, version);
    await verifyArm64(app);
    await signAndVerify(app);
    await createArchive(app, archive);
    await publish(app, archive, output, staging);

    return File('${output.path}/${version.archiveNameFor('macOS-arm64')}');
  } finally {
    await staging.delete(recursive: true);
  }
}

Future<void> verifyVersion(Directory app, AppVersion expected) async {
  final plist = '${app.path}/Contents/Info.plist';
  Future<String> value(String key) =>
      commandOutput('/usr/libexec/PlistBuddy', ['-c', 'Print :$key', plist]);
  final name = await value('CFBundleShortVersionString');
  final number = await value('CFBundleVersion');
  if (name != expected.name || number != expected.buildNumber) {
    throw StateError('App version $name+$number does not match pubspec.yaml.');
  }
}

Future<void> verifyArm64(Directory app) async {
  var binaries = 0;
  await for (final entry in app.list(recursive: true, followLinks: false)) {
    if (entry is! File) continue;
    final result = await Process.run('lipo', ['-archs', entry.path]);
    // Non-Mach-O files, such as fonts and images, are not architecture-aware.
    if (result.exitCode != 0) continue;
    final architectures = result.stdout.toString().trim();
    if (architectures != 'arm64') {
      throw StateError(
        'Found a non-arm64 binary: ${entry.path} ($architectures)',
      );
    }
    binaries++;
  }
  if (binaries == 0) {
    throw StateError('No executable binaries were found in the app.');
  }
  stdout.writeln('Validated $binaries binaries; all contain arm64 only.');
}

Future<void> signAndVerify(Directory app) async {
  // Keep the existing local signing flow and refresh the resource seal after
  // an incremental build.
  await runCommand('codesign', [
    '--force',
    '--sign',
    '-',
    '--preserve-metadata=identifier,entitlements,requirements,flags',
    app.path,
  ]);
  await runCommand('codesign', ['--verify', '--deep', '--strict', app.path]);
}

Future<void> createArchive(Directory app, File archive) async {
  await runCommand('ditto', [
    '-c',
    '-k',
    '--sequesterRsrc',
    '--keepParent',
    app.path,
    archive.path,
  ]);
  await runCommand('unzip', ['-tq', archive.path]);
}

Future<void> publish(
  Directory app,
  File archive,
  Directory output,
  Directory staging,
) async {
  final destination = Directory('${output.path}/$appName');
  final previous = Directory('${staging.path}/previous.app');
  if (await destination.exists()) await destination.rename(previous.path);
  try {
    await app.rename(destination.path);
    await archive.rename('${output.path}/${archive.uri.pathSegments.last}');
  } catch (_) {
    if (await destination.exists()) await destination.delete(recursive: true);
    if (await previous.exists()) await previous.rename(destination.path);
    rethrow;
  }
  final legacyArchive = File('${output.path}/Xlog-Decoder-macOS.zip');
  if (await legacyArchive.exists()) await legacyArchive.delete();
}
