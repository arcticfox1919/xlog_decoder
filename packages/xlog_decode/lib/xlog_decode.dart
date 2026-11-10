/// Pure Dart Mars xlog parsing, decryption, and decompression.
///
/// This library accepts bytes and returns decoded bytes with diagnostics.
/// Callers own file/network I/O, private-key provisioning, and key storage.
library;

export 'src/models.dart';
export 'src/stream_models.dart';
export 'src/xlog_decoder.dart';

export 'src/key_selection_exception.dart';
