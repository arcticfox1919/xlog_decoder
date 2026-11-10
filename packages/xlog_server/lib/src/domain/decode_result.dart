class DecodeResult {
  const DecodeResult({
    required this.filename,
    required this.outputBytes,
    required this.blockCount,
    required this.issueCount,
  });

  final String filename;
  final int outputBytes;
  final int blockCount;
  final int issueCount;
}
