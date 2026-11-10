import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:logging/logging.dart';

/// The executable owns output; embedding the server does not alter root logging.
StreamSubscription<LogRecord> configureServerLogging({
  String levelName = 'INFO',
}) {
  final level = Level.LEVELS
      .where((level) => level.name == levelName.toUpperCase())
      .firstOrNull;
  if (level == null) {
    throw const FormatException(
      'Invalid XLOG_LOG_LEVEL. Use INFO, FINE, WARNING, SEVERE or OFF.',
    );
  }
  Logger.root.level = level;
  return Logger.root.onRecord.listen((record) {
    final line = formatLogRecord(record);
    (record.level >= Level.WARNING ? stderr : stdout).writeln(line);
  });
}

String formatLogRecord(LogRecord record) => jsonEncode({
  'time': record.time.toUtc().toIso8601String(),
  'level': record.level.name,
  'logger': record.loggerName,
  if (record.object case final Map<String, Object?> fields)
    ...fields
  else
    'event': record.message,
  if (record.stackTrace != null) 'stackTrace': record.stackTrace.toString(),
});

/// Error messages can contain uploaded content, private keys or local paths.
/// Record the type and stack, rather than calling error.toString().
void logFailure(
  Logger logger,
  Level level,
  String event,
  Object error,
  StackTrace stack, {
  Map<String, Object?> fields = const {},
}) => logger.log(
  level,
  {'event': event, ...fields, 'errorType': error.runtimeType.toString()},
  null,
  stack,
);
