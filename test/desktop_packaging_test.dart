import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../scripts/build_windows.dart';
import '../scripts/src/desktop_build_support.dart';

void main() {
  late Directory project;
  late Directory runtime;
  const version = AppVersion('1.2.0', '1.2.0', '1');
  setUp(() async {
    project = await Directory.systemTemp.createTemp('desktop-package-');
    runtime = await Directory(p.join(project.path, 'runtime')).create();
    final release = p.join(project.path, 'build/windows/x64/runner/Release');
    for (final name in requiredWindowsFiles) {
      final file = File(
        p.join(
          name.endsWith('.dll') && name != 'flutter_windows.dll'
              ? runtime.path
              : release,
          name,
        ),
      );
      await file.parent.create(recursive: true);
      await file.writeAsString(name);
    }
    for (final name in ['README.md', 'README_EN.md', 'THIRD_PARTY_NOTICES']) {
      await File(p.join(project.path, name)).writeAsString(name);
    }
  });
  tearDown(() => project.delete(recursive: true));

  Future<Directory> crt(String relative, {bool complete = true}) async {
    final directory = await Directory(
      p.join(project.path, 'redist', relative),
    ).create(recursive: true);
    if (complete) {
      for (final dll in cppRuntimeFiles) {
        await File(p.join(directory.path, dll)).writeAsString(dll);
      }
    }
    return directory;
  }

  test(
    'Selects the latest desktop CRT and ignores OneCore and other architectures',
    () async {
      await crt('14.9.999/x64/Microsoft.VC143.CRT');
      final expected = await crt('14.44.35208/x64/Microsoft.VC143.CRT');
      await crt('14.50.1/onecore/x64/Microsoft.VC143.CRT');
      await crt('14.50.1/x86/Microsoft.VC143.CRT');
      await crt('14.50.1/arm64/Microsoft.VC143.CRT');
      await crt('14.50.1/debug_nonredist/x64/Microsoft.VC143.CRT');
      await crt('14.50.1/x64/Microsoft.VC143.CRT', complete: false);
      await crt('onecore/x64/Microsoft.VC143.CRT');
      await crt('not-a-version/x64/Microsoft.VC143.CRT');
      final selected = await selectCppRuntime(
        Directory(p.join(project.path, 'redist')),
      );
      expect(selected.path, expected.path);
    },
  );

  test('Rejects installations containing only a OneCore runtime', () async {
    await crt('14.44.35208/onecore/x64/Microsoft.VC143.CRT');
    await expectLater(
      selectCppRuntime(Directory(p.join(project.path, 'redist'))),
      throwsStateError,
    );
  });

  test(
    'Windows ZIP preserves the bundle directory and includes runtime DLLs',
    () async {
      final result = await packageWindowsRelease(
        project,
        version,
        runtime: runtime,
      );
      expect(p.basename(result.path), 'Xlog-Decoder-1.2.0-Windows-x64.zip');
      final archive = ZipDecoder().decodeBytes(
        await result.readAsBytes(),
        verify: true,
      );
      for (final name in [
        ...requiredWindowsFiles,
        'README.md',
        'README_EN.md',
        'THIRD_PARTY_NOTICES',
      ]) {
        final file = archive.findFile('XlogDecoder/$name');
        expect(file, isNotNull, reason: name);
        expect(String.fromCharCodes(file!.content), name);
      }
      expect(await result.parent.list().length, 1);
    },
  );

  test(
    'Missing runtime DLL fails without replacing a previous archive',
    () async {
      final original = await packageWindowsRelease(
        project,
        version,
        runtime: runtime,
      );
      final bytes = await original.readAsBytes();
      await File(p.join(runtime.path, 'vcruntime140_1.dll')).delete();
      await expectLater(
        packageWindowsRelease(project, version, runtime: runtime),
        throwsStateError,
      );
      expect(await original.readAsBytes(), bytes);
      expect(await original.parent.list().length, 1);
    },
  );

  test(
    'Shared version reader and archive names agree across platforms',
    () async {
      await File(
        p.join(project.path, 'pubspec.yaml'),
      ).writeAsString('version: 1.2.0-beta.1\n');
      final parsed = await readVersion(project);
      expect(
        parsed.archiveNameFor('Windows-x64'),
        'Xlog-Decoder-1.2.0-beta.1-Windows-x64.zip',
      );
      expect(
        parsed.archiveNameFor('macOS-arm64'),
        'Xlog-Decoder-1.2.0-beta.1-macOS-arm64.zip',
      );
    },
  );
}
