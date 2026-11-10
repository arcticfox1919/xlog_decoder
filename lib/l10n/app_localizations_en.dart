// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Xlog Decoder';

  @override
  String get appSubtitle => 'Narwal log decoding tool';

  @override
  String get localProcessing => 'Local processing';

  @override
  String get privacyNote =>
      'Processed locally  ·  Originals preserved  ·  Unique output names';

  @override
  String get language => 'Language';

  @override
  String get systemLanguage => 'System default';

  @override
  String get languageSaveError =>
      'Could not save the language setting. Please try again.';

  @override
  String get languageLoadError =>
      'Could not restore the language setting. Using the system language.';

  @override
  String get loadSettingsError =>
      'Could not read saved settings. Select the directory or enter the private key again.';

  @override
  String get saveSettingsError =>
      'Could not save settings. Check local storage permissions.';

  @override
  String dialogError(String error) {
    return 'Could not open the file dialog: $error';
  }

  @override
  String get dropFoldersError =>
      'Drop log or ZIP files. Dropping folders is not supported.';

  @override
  String dropReadError(String error) {
    return 'Could not read dropped files: $error';
  }

  @override
  String get addLogs => 'Add logs';

  @override
  String get multipleSelection => 'Multiple files';

  @override
  String get decodingLogs => 'Decoding logs…';

  @override
  String get releaseToDecode => 'Release to decode';

  @override
  String get dropLogs => 'Drop logs or ZIP files';

  @override
  String get resultsBelow => 'Results will appear below';

  @override
  String get dropDescription => 'Extract, decrypt, and generate readable logs';

  @override
  String get selectFiles => 'Select files';

  @override
  String get decoderSettings => 'Decode settings';

  @override
  String get autoSave => 'Auto-save';

  @override
  String get outputDirectory => 'Output directory';

  @override
  String get chooseOutputDirectory => 'Click to choose an output directory';

  @override
  String get sourceDirectory => 'Same as source file';

  @override
  String get resetDirectory => 'Reset';

  @override
  String get privateKey => 'Private key';

  @override
  String get optional => 'Optional';

  @override
  String get privateKeyHint => '64 hexadecimal characters';

  @override
  String get hidePrivateKey => 'Hide private key';

  @override
  String get showPrivateKey => 'Show private key';

  @override
  String get importPrivateKey => 'Import key from file';

  @override
  String get privateKeyHelp =>
      'Leave blank for unencrypted logs. The key is encrypted on this device. Clear the field to delete it.';

  @override
  String get invalidPrivateKey =>
      'Enter a valid 64-character hexadecimal private key, or leave blank for unencrypted logs.';

  @override
  String get logFiles => 'Logs or ZIP';

  @override
  String get allFiles => 'All files';

  @override
  String get setOutputDirectory => 'Set output directory';

  @override
  String get processingHistory => 'Processing history';

  @override
  String get clearHistory => 'Clear history';

  @override
  String get noHistory => 'No files processed yet';

  @override
  String get outputHelp =>
      'Creates .log files; ZIP results go into a separate folder';

  @override
  String get statusQueued => 'Queued';

  @override
  String get statusRunning => 'Processing';

  @override
  String get statusSuccess => 'Completed';

  @override
  String get statusWarning => 'Partially recovered';

  @override
  String get statusFailure => 'Failed';

  @override
  String get copyOutputPath => 'Copy output path';

  @override
  String get outputPathCopied => 'Output path copied';

  @override
  String get inputMissing => 'Input file not found. Select it again.';

  @override
  String get zipEntryTooLarge => 'A log inside the ZIP exceeds 256 MiB.';

  @override
  String get zipEntryUnreadable => 'Could not read a log inside the ZIP.';

  @override
  String get zipChecksumFailed =>
      'ZIP checksum failed. The log may be corrupted.';

  @override
  String get zipNoLogs => 'No .xlog, .log, or .bin files found in the ZIP.';

  @override
  String get noLogContent =>
      'No log content recovered. Check the format and private key.';

  @override
  String taskCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count tasks',
      one: '1 task',
    );
    return '$_temp0';
  }

  @override
  String generatedLogs(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Generated $count logs',
      one: 'Generated 1 log',
    );
    return '$_temp0';
  }

  @override
  String failedLogs(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count failed',
      one: '1 failed',
    );
    return '$_temp0';
  }

  @override
  String skippedEntries(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Skipped $count non-log entries',
      one: 'Skipped 1 non-log entry',
    );
    return '$_temp0';
  }

  @override
  String logBlocks(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count log blocks',
      one: '1 log block',
    );
    return '$_temp0';
  }

  @override
  String recoveryHints(int count, String details) {
    return 'Recovery notes ($count)\n$details';
  }

  @override
  String get languageName => 'English';
}
