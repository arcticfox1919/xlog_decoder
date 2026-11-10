import '../../domain/stored_result.dart';

abstract interface class JobStorage {
  Future<void> initialize();
  Future<String> createWorkspace(String id);
  Future<void> writeUpload(
    String id,
    Stream<List<int>> source, {
    required int maxBytes,
    required Duration timeout,
  });
  Future<void> deleteInput(String id);
  Future<void> deleteWorkspace(String id);
  Future<StoredResult> readResult(String id, String filename);
}
