import 'dart:convert';

import 'package:logging/logging.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';
import 'package:xlog_server/src/diagnostics/server_logging.dart';
import 'package:xlog_server/src/http/middleware/error_handling.dart';
import 'package:xlog_server/src/http/middleware/request_logging.dart';

void main() {
  late Level previous;
  setUp(() {
    previous = Logger.root.level;
    Logger.root.level = Level.ALL;
  });
  tearDown(() => Logger.root.level = previous);

  test('request failures are traceable without logging raw input', () async {
    final records = <LogRecord>[];
    final subscription = Logger.root.onRecord.listen(records.add);
    addTearDown(subscription.cancel);
    final handler = const Pipeline()
        .addMiddleware(requestLogging())
        .addMiddleware(errorHandling())
        .addHandler((_) => throw StateError('private-key-and-log-content'));
    final response = await handler(
      Request(
        'POST',
        Uri.parse('http://localhost/api/jobs?filename=private-name.xlog'),
      ),
    );
    expect(response.statusCode, 500);
    final requestId = response.headers['x-request-id'];
    expect(requestId, isNotEmpty);
    final logs = records
        .map((r) => jsonDecode(formatLogRecord(r)) as Map)
        .toList();
    final failure = logs.singleWhere((log) => log['event'] == 'http.failed');
    final request = logs.singleWhere((log) => log['event'] == 'http.response');
    expect(failure['requestId'], requestId);
    expect(failure['errorType'], 'StateError');
    expect(failure['stackTrace'], isNotEmpty);
    expect(request['requestId'], requestId);
    expect(request['status'], 500);
    expect(request['responseMs'], greaterThanOrEqualTo(0));
    final output = jsonEncode(logs);
    expect(output, isNot(contains('private-key-and-log-content')));
    expect(output, isNot(contains('private-name.xlog')));
  });

  test('polling uses debug level and each request gets its own ID', () async {
    final records = <LogRecord>[];
    final subscription = Logger.root.onRecord.listen(records.add);
    addTearDown(subscription.cancel);
    final handler = const Pipeline()
        .addMiddleware(requestLogging())
        .addHandler((_) => Response.ok('ok'));
    final first = await handler(
      Request('GET', Uri.parse('http://localhost/api/health')),
    );
    final second = await handler(
      Request('GET', Uri.parse('http://localhost/api/health')),
    );
    expect(
      first.headers['x-request-id'],
      isNot(second.headers['x-request-id']),
    );
    expect(records.map((r) => r.level), everyElement(Level.FINE));
  });

  test('records are single-line JSON with UTC timestamps', () {
    final record = LogRecord(
      Level.INFO,
      'job.completed',
      'xlog.jobs',
      null,
      null,
      null,
      {'event': 'job.completed', 'jobId': 'job-1'},
    );
    final line = formatLogRecord(record);
    final json = jsonDecode(line) as Map;
    expect(json['event'], 'job.completed');
    expect(json['jobId'], 'job-1');
    expect(json['level'], 'INFO');
    expect(json['time'], endsWith('Z'));
    expect(line, isNot(contains('\n')));
  });
}
