/// Automatic key selection could not establish one decoded block content.
/// No key material or decrypted candidate bytes are included in diagnostics.
class XlogKeySelectionException implements Exception {
  const XlogKeySelectionException(this.reason);
  final XlogKeySelectionFailure reason;

  @override
  String toString() => 'XlogKeySelectionException: ${reason.name}';
}

enum XlogKeySelectionFailure { missingKeys, noMatchingKey, ambiguousKeys }
