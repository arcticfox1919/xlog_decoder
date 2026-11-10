class StoredResult {
  const StoredResult({
    required this.filename,
    required this.length,
    required this.openRead,
  });

  final String filename;
  final int length;
  final Stream<List<int>> Function() openRead;
}
