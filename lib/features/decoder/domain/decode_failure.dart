/// Stable error codes keep worker isolates and stored results language neutral.
enum DecodeErrorCode {
  inputMissing,
  zipEntryTooLarge,
  zipEntryUnreadable,
  zipChecksumFailed,
  zipNoLogs,
  noLogContent,
}

class DecodeFailure extends FormatException {
  const DecodeFailure(this.code, {this.detail = ''}) : super('Decode failed');

  final DecodeErrorCode code;
  final String detail;
}

enum DecoderConfigurationError { invalidPrivateKey }
