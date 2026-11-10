import 'dart:io';

import 'package:path/path.dart' as p;

import '../../application/ports/job_storage.dart';
import '../../domain/service_exception.dart';
import '../../domain/stored_result.dart';

/// Owns the server-generated workspace tree and the fixed upload filename.
class FileJobStorage implements JobStorage {
  FileJobStorage(this.root);

  final Directory root;

  @override
  Future<void> initialize() => root.create(recursive: true);

  Directory _workspace(String id) {
    if (!RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(id)) {
      throw ArgumentError.value(id, 'id', 'Expected a server-generated ID');
    }
    return Directory(p.join(root.path, id));
  }

  Future<Directory> _checkedWorkspace(String id) async {
    final directory = _workspace(id);
    final type = await FileSystemEntity.type(
      directory.path,
      followLinks: false,
    );
    if (type != FileSystemEntityType.notFound &&
        type != FileSystemEntityType.directory) {
      throw FileSystemException(
        'Expected a workspace directory',
        directory.path,
      );
    }
    return directory;
  }

  @override
  Future<String> createWorkspace(String id) async {
    final directory = await _checkedWorkspace(id);
    await directory.create();
    return directory.path;
  }

  @override
  Future<void> writeUpload(
    String id,
    Stream<List<int>> source, {
    required int maxBytes,
    required Duration timeout,
  }) async {
    final directory = await _checkedWorkspace(id);
    final input = File(p.join(directory.path, 'input'));
    if (await FileSystemEntity.type(input.path, followLinks: false) ==
        FileSystemEntityType.link) {
      throw FileSystemException('Input must not be a link', input.path);
    }
    RandomAccessFile? writer;
    try {
      writer = await input.open(mode: FileMode.writeOnly);
      var length = 0;
      await for (final chunk in source.timeout(timeout)) {
        length += chunk.length;
        if (length > maxBytes) {
          throw const ServiceException(ServiceError.uploadTooLarge);
        }
        await writer.writeFrom(chunk);
      }
      final completedWriter = writer;
      writer = null;
      await completedWriter.close();
      if (length == 0) {
        throw const ServiceException(ServiceError.emptyUpload);
      }
    } catch (error, stack) {
      // Preserve the upload failure (including 413/timeout semantics). The
      // application will also attempt workspace cleanup and report failures.
      try {
        await writer?.close();
      } catch (_) {}
      try {
        if (await input.exists()) await input.delete();
      } catch (_) {}
      Error.throwWithStackTrace(error, stack);
    }
  }

  @override
  Future<void> deleteInput(String id) async {
    final directory = await _checkedWorkspace(id);
    try {
      await File(p.join(directory.path, 'input')).delete();
    } on FileSystemException catch (error) {
      if (error.osError?.errorCode != 2) rethrow;
    }
  }

  @override
  Future<void> deleteWorkspace(String id) async {
    final directory = await _checkedWorkspace(id);
    try {
      await directory.delete(recursive: true);
    } on FileSystemException catch (error) {
      if (error.osError?.errorCode != 2) rethrow;
    }
  }

  @override
  Future<StoredResult> readResult(String id, String filename) async {
    if (filename.isEmpty ||
        filename == '.' ||
        filename == '..' ||
        !RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(filename)) {
      throw ArgumentError.value(
        filename,
        'filename',
        'Expected an output name',
      );
    }
    final directory = await _checkedWorkspace(id);
    final file = File(p.join(directory.path, filename));
    if (await FileSystemEntity.type(file.path, followLinks: false) !=
        FileSystemEntityType.file) {
      throw const ServiceException(ServiceError.resultExpired);
    }
    try {
      return StoredResult(
        filename: filename,
        length: await file.length(),
        openRead: file.openRead,
      );
    } on FileSystemException catch (error) {
      // A concurrent cleanup may win between the type check and stat.
      if (error.osError?.errorCode == 2) {
        throw const ServiceException(ServiceError.resultExpired);
      }
      rethrow;
    }
  }
}
