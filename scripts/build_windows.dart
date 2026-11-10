import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;

import 'src/desktop_build_support.dart';

const usage = '''
Usage: dart scripts/build_windows.dart

Build a Windows x64 release with Flutter and Visual Studio C++ tools.
Output: build/windows/dist/Xlog-Decoder-<version>-Windows-x64.zip.
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
    if (!Platform.isWindows) {
      throw StateError(
        'Run this script on Windows with Visual Studio C++ tools.',
      );
    }
    final project = File.fromUri(Platform.script).parent.parent;
    final version = await readVersion(project);
    stdout.writeln('Building Windows x64 release ${version.full}...');
    await runCommand(findFlutter(project), [
      'build',
      'windows',
      '--release',
      '--build-name',
      version.name,
      '--build-number',
      version.buildNumber,
    ], workingDirectory: project.path);
    final archive = await packageWindowsRelease(
      project,
      version,
      runtime: await findCppRuntime(),
    );
    stdout.writeln('Packaging complete: ${archive.path}');
  } catch (error) {
    stderr.writeln('Packaging failed: $error');
    exitCode = 1;
  }
}

Future<Directory> findCppRuntime() async {
  final programFiles = Platform.environment['ProgramFiles(x86)'];
  if (programFiles == null) throw StateError('ProgramFiles(x86) is not set.');
  final vswhere = p.join(
    programFiles,
    'Microsoft Visual Studio',
    'Installer',
    'vswhere.exe',
  );
  final installation = await commandOutput(vswhere, [
    '-latest',
    '-products',
    '*',
    '-requires',
    'Microsoft.VisualStudio.Component.VC.Tools.x86.x64',
    '-property',
    'installationPath',
  ]);
  if (installation.isEmpty) {
    throw StateError('Visual Studio C++ tools not found.');
  }
  final redist = Directory(p.join(installation, 'VC', 'Redist', 'MSVC'));
  final candidates = <Directory>[];
  await for (final entry in redist.list(recursive: true, followLinks: false)) {
    if (entry is Directory &&
        p.basename(entry.parent.path) == 'x64' &&
        RegExp(r'^Microsoft\.VC\d+\.CRT$').hasMatch(p.basename(entry.path))) {
      candidates.add(entry);
    }
  }
  if (candidates.isEmpty) {
    throw StateError('Visual C++ x64 runtime DLLs not found.');
  }
  candidates.sort((a, b) => _compareRuntimeVersions(a, b));
  return candidates.last;
}

int _compareRuntimeVersions(Directory a, Directory b) {
  List<int> parts(Directory dir) =>
      p.basename(dir.parent.parent.path).split('.').map(int.parse).toList();
  final left = parts(a);
  final right = parts(b);
  for (var i = 0; i < left.length && i < right.length; i++) {
    final difference = left[i].compareTo(right[i]);
    if (difference != 0) return difference;
  }
  return left.length.compareTo(right.length);
}

Future<File> packageWindowsRelease(
  Directory project,
  AppVersion version, {
  required Directory runtime,
}) async {
  final release = Directory(
    p.join(project.path, 'build', 'windows', 'x64', 'runner', 'Release'),
  );
  final output = await Directory(
    p.join(project.path, 'build', 'windows', 'dist'),
  ).create(recursive: true);
  final staging = await output.createTemp('.package.');
  try {
    final bundle = await Directory(
      p.join(staging.path, 'XlogDecoder'),
    ).create();
    await _copyDirectory(release, bundle);
    await for (final entry in runtime.list(followLinks: false)) {
      if (entry is File && p.extension(entry.path).toLowerCase() == '.dll') {
        await entry.copy(p.join(bundle.path, p.basename(entry.path)));
      }
    }
    for (final name in ['README.md', 'README_EN.md', 'THIRD_PARTY_NOTICES']) {
      await File(p.join(project.path, name)).copy(p.join(bundle.path, name));
    }
    for (final name in requiredWindowsFiles) {
      if (!await File(p.join(bundle.path, name)).exists()) {
        throw StateError('Missing required package file: $name');
      }
    }
    final archive = File(
      p.join(staging.path, version.archiveNameFor('Windows-x64')),
    );
    final encoder = ZipFileEncoder()..create(archive.path);
    try {
      await encoder.addDirectory(
        bundle,
        includeDirName: true,
        followLinks: false,
      );
    } finally {
      await encoder.close();
    }
    return await archive.rename(p.join(output.path, p.basename(archive.path)));
  } finally {
    await staging.delete(recursive: true);
  }
}

const requiredWindowsFiles = [
  'xlog_decoder.exe',
  'flutter_windows.dll',
  'data/app.so',
  'data/icudtl.dat',
  'msvcp140.dll',
  'vcruntime140.dll',
  'vcruntime140_1.dll',
];

Future<void> _copyDirectory(Directory source, Directory destination) async {
  await for (final entry in source.list(followLinks: false)) {
    final target = p.join(destination.path, p.basename(entry.path));
    if (entry is Directory) {
      await _copyDirectory(entry, await Directory(target).create());
    } else if (entry is File) {
      await entry.copy(target);
    } else {
      throw StateError('Unexpected link in build output: ${entry.path}');
    }
  }
}
