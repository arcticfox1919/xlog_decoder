class ZipLimits {
  const ZipLimits({
    this.maxEntries = 128,
    this.maxCentralDirectoryBytes = 1024 * 1024,
    this.maxEntryBytes = 256 * 1024 * 1024,
    this.maxExpandedBytes = 512 * 1024 * 1024,
  });

  final int maxEntries;
  final int maxCentralDirectoryBytes;
  final int maxEntryBytes;
  final int maxExpandedBytes;
}
