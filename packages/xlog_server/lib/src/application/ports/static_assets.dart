import '../../domain/stored_result.dart';

/// Read-only public assets, independent of how and where they are stored.
abstract interface class StaticAssets {
  Future<StoredResult?> read(String relative);
}
