import '../../../l10n/app_localizations.dart';
import '../domain/decode_failure.dart';

String decodeFailureText(AppLocalizations l10n, DecodeFailure failure) {
  final message = switch (failure.code) {
    DecodeErrorCode.inputMissing => l10n.inputMissing,
    DecodeErrorCode.zipEntryTooLarge => l10n.zipEntryTooLarge,
    DecodeErrorCode.zipEntryUnreadable => l10n.zipEntryUnreadable,
    DecodeErrorCode.zipChecksumFailed => l10n.zipChecksumFailed,
    DecodeErrorCode.zipNoLogs => l10n.zipNoLogs,
    DecodeErrorCode.noLogContent => l10n.noLogContent,
  };
  return failure.detail.isEmpty ? message : '$message\n${failure.detail}';
}
