import 'dart:io';

import 'package:path/path.dart' as p;

import '../../domain/stored_result.dart';
import '../../application/ports/static_assets.dart';

/// Reads public assets without permitting lexical or symlink path escapes.
class StaticFileStore implements StaticAssets {
  const StaticFileStore(this.root, {required this.privateDirectory});
  final Directory root;
  final Directory privateDirectory;

  @override
  Future<StoredResult?> read(String relative) async {
    final rootPath = p.normalize(root.absolute.path);
    final target = p.normalize(p.join(rootPath, relative));
    if (!p.isWithin(rootPath, target)) return null;
    final file = File(target);
    if (!await root.exists() || !await file.exists()) return null;
    final actualRoot = await root.resolveSymbolicLinks();
    final actualFile = await file.resolveSymbolicLinks();
    if (!p.isWithin(actualRoot, actualFile)) return null;
    if (await privateDirectory.exists()) {
      final privatePath = await privateDirectory.resolveSymbolicLinks();
      if (p.equals(privatePath, actualFile) ||
          p.isWithin(privatePath, actualFile)) {
        return null;
      }
    }
    return StoredResult(
      filename: p.basename(target),
      length: await file.length(),
      openRead: file.openRead,
    );
  }
}
