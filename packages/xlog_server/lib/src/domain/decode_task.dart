class DecodeTask {
  DecodeTask({
    required this.workspacePath,
    required this.name,
    Iterable<String> privateKeysHex = const [],
    required this.maxOutputBytes,
  }) : privateKeysHex = List.unmodifiable(privateKeysHex);

  final String workspacePath;
  final String name;
  final List<String> privateKeysHex;
  final int maxOutputBytes;
}
