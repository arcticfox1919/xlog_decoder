import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('zh'),
  ];

  /// appTitle
  ///
  /// In en, this message translates to:
  /// **'Xlog Decoder'**
  String get appTitle;

  /// appSubtitle
  ///
  /// In en, this message translates to:
  /// **'Narwal log decoding tool'**
  String get appSubtitle;

  /// localProcessing
  ///
  /// In en, this message translates to:
  /// **'Local processing'**
  String get localProcessing;

  /// privacyNote
  ///
  /// In en, this message translates to:
  /// **'Processed locally  ·  Originals preserved  ·  Unique output names'**
  String get privacyNote;

  /// language
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// systemLanguage
  ///
  /// In en, this message translates to:
  /// **'System default'**
  String get systemLanguage;

  /// languageSaveError
  ///
  /// In en, this message translates to:
  /// **'Could not save the language setting. Please try again.'**
  String get languageSaveError;

  /// languageLoadError
  ///
  /// In en, this message translates to:
  /// **'Could not restore the language setting. Using the system language.'**
  String get languageLoadError;

  /// loadSettingsError
  ///
  /// In en, this message translates to:
  /// **'Could not read saved settings. Select the directory or enter the private key again.'**
  String get loadSettingsError;

  /// saveSettingsError
  ///
  /// In en, this message translates to:
  /// **'Could not save settings. Check local storage permissions.'**
  String get saveSettingsError;

  /// dialogError
  ///
  /// In en, this message translates to:
  /// **'Could not open the file dialog: {error}'**
  String dialogError(String error);

  /// dropFoldersError
  ///
  /// In en, this message translates to:
  /// **'Drop log or ZIP files. Dropping folders is not supported.'**
  String get dropFoldersError;

  /// dropReadError
  ///
  /// In en, this message translates to:
  /// **'Could not read dropped files: {error}'**
  String dropReadError(String error);

  /// addLogs
  ///
  /// In en, this message translates to:
  /// **'Add logs'**
  String get addLogs;

  /// multipleSelection
  ///
  /// In en, this message translates to:
  /// **'Multiple files'**
  String get multipleSelection;

  /// decodingLogs
  ///
  /// In en, this message translates to:
  /// **'Decoding logs…'**
  String get decodingLogs;

  /// releaseToDecode
  ///
  /// In en, this message translates to:
  /// **'Release to decode'**
  String get releaseToDecode;

  /// dropLogs
  ///
  /// In en, this message translates to:
  /// **'Drop logs or ZIP files'**
  String get dropLogs;

  /// resultsBelow
  ///
  /// In en, this message translates to:
  /// **'Results will appear below'**
  String get resultsBelow;

  /// dropDescription
  ///
  /// In en, this message translates to:
  /// **'Extract, decrypt, and generate readable logs'**
  String get dropDescription;

  /// selectFiles
  ///
  /// In en, this message translates to:
  /// **'Select files'**
  String get selectFiles;

  /// decoderSettings
  ///
  /// In en, this message translates to:
  /// **'Decode settings'**
  String get decoderSettings;

  /// autoSave
  ///
  /// In en, this message translates to:
  /// **'Auto-save'**
  String get autoSave;

  /// outputDirectory
  ///
  /// In en, this message translates to:
  /// **'Output directory'**
  String get outputDirectory;

  /// chooseOutputDirectory
  ///
  /// In en, this message translates to:
  /// **'Click to choose an output directory'**
  String get chooseOutputDirectory;

  /// sourceDirectory
  ///
  /// In en, this message translates to:
  /// **'Same as source file'**
  String get sourceDirectory;

  /// resetDirectory
  ///
  /// In en, this message translates to:
  /// **'Reset'**
  String get resetDirectory;

  /// privateKey
  ///
  /// In en, this message translates to:
  /// **'Private key'**
  String get privateKey;

  /// optional
  ///
  /// In en, this message translates to:
  /// **'Optional'**
  String get optional;

  /// privateKeyHint
  ///
  /// In en, this message translates to:
  /// **'64 hexadecimal characters'**
  String get privateKeyHint;

  /// hidePrivateKey
  ///
  /// In en, this message translates to:
  /// **'Hide private key'**
  String get hidePrivateKey;

  /// showPrivateKey
  ///
  /// In en, this message translates to:
  /// **'Show private key'**
  String get showPrivateKey;

  /// importPrivateKey
  ///
  /// In en, this message translates to:
  /// **'Import key from file'**
  String get importPrivateKey;

  /// privateKeyHelp
  ///
  /// In en, this message translates to:
  /// **'Leave blank for unencrypted logs. The key is encrypted on this device. Clear the field to delete it.'**
  String get privateKeyHelp;

  /// invalidPrivateKey
  ///
  /// In en, this message translates to:
  /// **'Enter a valid 64-character hexadecimal private key, or leave blank for unencrypted logs.'**
  String get invalidPrivateKey;

  /// logFiles
  ///
  /// In en, this message translates to:
  /// **'Logs or ZIP'**
  String get logFiles;

  /// allFiles
  ///
  /// In en, this message translates to:
  /// **'All files'**
  String get allFiles;

  /// setOutputDirectory
  ///
  /// In en, this message translates to:
  /// **'Set output directory'**
  String get setOutputDirectory;

  /// processingHistory
  ///
  /// In en, this message translates to:
  /// **'Processing history'**
  String get processingHistory;

  /// clearHistory
  ///
  /// In en, this message translates to:
  /// **'Clear history'**
  String get clearHistory;

  /// noHistory
  ///
  /// In en, this message translates to:
  /// **'No files processed yet'**
  String get noHistory;

  /// outputHelp
  ///
  /// In en, this message translates to:
  /// **'Creates .log files; ZIP results go into a separate folder'**
  String get outputHelp;

  /// statusQueued
  ///
  /// In en, this message translates to:
  /// **'Queued'**
  String get statusQueued;

  /// statusRunning
  ///
  /// In en, this message translates to:
  /// **'Processing'**
  String get statusRunning;

  /// statusSuccess
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get statusSuccess;

  /// statusWarning
  ///
  /// In en, this message translates to:
  /// **'Partially recovered'**
  String get statusWarning;

  /// statusFailure
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get statusFailure;

  /// copyOutputPath
  ///
  /// In en, this message translates to:
  /// **'Copy output path'**
  String get copyOutputPath;

  /// outputPathCopied
  ///
  /// In en, this message translates to:
  /// **'Output path copied'**
  String get outputPathCopied;

  /// inputMissing
  ///
  /// In en, this message translates to:
  /// **'Input file not found. Select it again.'**
  String get inputMissing;

  /// zipEntryTooLarge
  ///
  /// In en, this message translates to:
  /// **'A log inside the ZIP exceeds 256 MiB.'**
  String get zipEntryTooLarge;

  /// zipEntryUnreadable
  ///
  /// In en, this message translates to:
  /// **'Could not read a log inside the ZIP.'**
  String get zipEntryUnreadable;

  /// zipChecksumFailed
  ///
  /// In en, this message translates to:
  /// **'ZIP checksum failed. The log may be corrupted.'**
  String get zipChecksumFailed;

  /// zipNoLogs
  ///
  /// In en, this message translates to:
  /// **'No .xlog, .log, or .bin files found in the ZIP.'**
  String get zipNoLogs;

  /// noLogContent
  ///
  /// In en, this message translates to:
  /// **'No log content recovered. Check the format and private key.'**
  String get noLogContent;

  /// taskCount
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 task} other{{count} tasks}}'**
  String taskCount(int count);

  /// generatedLogs
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Generated 1 log} other{Generated {count} logs}}'**
  String generatedLogs(int count);

  /// failedLogs
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 failed} other{{count} failed}}'**
  String failedLogs(int count);

  /// skippedEntries
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Skipped 1 non-log entry} other{Skipped {count} non-log entries}}'**
  String skippedEntries(int count);

  /// logBlocks
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 log block} other{{count} log blocks}}'**
  String logBlocks(int count);

  /// recoveryHints
  ///
  /// In en, this message translates to:
  /// **'Recovery notes ({count})\n{details}'**
  String recoveryHints(int count, String details);

  /// Native name of this language, displayed in the language menu.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get languageName;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
