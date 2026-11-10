import 'package:web/web.dart' as web;

import '../features/decoder/domain/decoder_api.dart';

/// Keeps the native browser File outside application state and API contracts.
class BrowserUploadFile implements UploadFile {
  const BrowserUploadFile(this.file);

  final web.File file;

  @override
  String get name => file.name;

  @override
  int get size => file.size;
}
