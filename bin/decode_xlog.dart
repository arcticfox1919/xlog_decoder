import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as p;
import 'package:xlog_decoder/xlog_decoder.dart';

Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption(
      'key-file',
      help: 'File containing the server private key in hex.',
    )
    ..addOption('legacy', allowed: ['python', 'c'], defaultsTo: 'python')
    ..addFlag(
      'strict',
      negatable: false,
      help: 'Stop at the first damaged block.',
    )
    ..addFlag('help', abbr: 'h', negatable: false);

  try {
    final args = parser.parse(arguments);
    if (args.flag('help') || args.rest.isEmpty) {
      stdout.writeln(
        'Usage: dart run bin/decode_xlog.dart [options] input [output]\n'
        'Input may be a file or a directory (all *.xlog files).\n${parser.usage}',
      );
      if (!args.flag('help')) exitCode = 64;
      return;
    }
    if (args.rest.length > 2) throw const FormatException('Too many paths');
    final keyPath = args.option('key-file');
    final decoder = XlogDecoder(
      privateKeyHex: keyPath == null
          ? Platform.environment['XLOG_PRIVATE_KEY']
          : await File(keyPath).readAsString(),
      legacyFormat: XlogLegacyFormat.values.byName(args.option('legacy')!),
      strict: args.flag('strict'),
    );
    final input = args.rest.first;
    final files = <File>[];
    if (await Directory(input).exists()) {
      if (args.rest.length == 2) {
        throw const FormatException(
          'Directory input does not accept an output path',
        );
      }
      await for (final entity in Directory(input).list(followLinks: false)) {
        if (entity is File && entity.path.toLowerCase().endsWith('.xlog')) {
          files.add(entity);
        }
      }
      files.sort((a, b) => a.path.compareTo(b.path));
      if (files.isEmpty) throw const FormatException('No .xlog files found');
    } else {
      files.add(File(input));
    }

    for (final file in files) {
      try {
        final output = File(
          args.rest.length == 2
              ? args.rest[1]
              : p.join(
                  p.dirname(file.path),
                  '${p.basenameWithoutExtension(file.path)}.log',
                ),
        );
        if (await output.exists() &&
            await FileSystemEntity.identical(file.path, output.path)) {
          throw const FormatException('Output must differ from input');
        }
        final result = decoder.decode(await file.readAsBytes());
        for (final issue in result.issues) {
          stderr.writeln('${file.path}: $issue');
        }
        if (result.blocks.isEmpty) {
          throw const FormatException('No decodable xlog blocks found');
        }
        await output.writeAsBytes(result.bytes);
        stdout.writeln(
          '${file.path} -> ${output.path} '
          '(${result.blocks.length} blocks, ${result.bytes.length} bytes)',
        );
        if (result.issues.isNotEmpty) exitCode = 1;
      } on Exception catch (error) {
        stderr.writeln('${file.path}: $error');
        exitCode = 1;
      }
    }
  } on FormatException catch (error) {
    stderr.writeln('${error.message}\n${parser.usage}');
    exitCode = 64;
  } on ArgumentError {
    stderr.writeln('Invalid decoder configuration or private key');
    exitCode = 64;
  } on FileSystemException catch (error) {
    stderr.writeln(error);
    exitCode = 1;
  }
}
