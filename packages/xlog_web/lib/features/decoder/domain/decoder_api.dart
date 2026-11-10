import 'models.dart';

/// File metadata needed by the upload workflow, without a browser dependency.
abstract interface class UploadFile {
  String get name;
  int get size;
}

abstract interface class DecoderApi {
  Future<int> health();
  Future<RemoteJob> job(String id);
  Future<void> cancel(String id);
  Future<RemoteJob> upload(
    UploadFile file, {
    required void Function(double) onProgress,
  });
  String? downloadLink(RemoteJob job);
  void close();
}

typedef DecoderApiFactory = DecoderApi Function(Uri baseUri);
