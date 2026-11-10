import 'package:path/path.dart' as p;

/// ZIP member paths are labels only and never become extraction paths.
String outputStem(String name, {int? maxLength = 100}) {
  final basename = p.posix.basename(name.replaceAll('\\', '/'));
  final stem = p.posix
      .basenameWithoutExtension(basename)
      .replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
  return maxLength == null
      ? stem
      : stem.substring(0, stem.length.clamp(0, maxLength));
}
