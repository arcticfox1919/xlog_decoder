import 'dart:io';

import 'package:path/path.dart' as p;

import 'server_configuration_exception.dart';

/// Also resolves existing ancestors, so a not-yet-created public directory
/// cannot hide its eventual location behind a parent symlink.
Future<void> rejectPublicConfigurationFile(
  File file,
  Directory? webRoot,
  String field,
) async {
  if (webRoot == null) return;
  bool contains(String root, String target) =>
      p.equals(root, target) || p.isWithin(root, target);
  try {
    if (contains(
          p.normalize(webRoot.absolute.path),
          p.normalize(file.absolute.path),
        ) ||
        contains(await _realPath(webRoot.path), await _realPath(file.path))) {
      throw ServerConfigurationException(field, 'must be outside webRoot');
    }
  } on FileSystemException {
    throw ServerConfigurationException(field, 'could not validate path');
  }
}

Future<String> _realPath(String path) async {
  final absolute = p.normalize(p.absolute(path));
  if (await FileSystemEntity.type(absolute) != FileSystemEntityType.notFound) {
    return File(absolute).resolveSymbolicLinks();
  }
  final parent = p.dirname(absolute);
  if (parent == absolute) return absolute;
  return p.join(await _realPath(parent), p.basename(absolute));
}
