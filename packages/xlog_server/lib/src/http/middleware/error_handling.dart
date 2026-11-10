import 'dart:async';

import 'package:shelf/shelf.dart';
import 'package:logging/logging.dart';

import '../../diagnostics/server_logging.dart';

import '../../domain/service_exception.dart';
import '../http_failure.dart';
import '../responses.dart';

Middleware errorHandling() =>
    (inner) => (request) async {
      try {
        return await inner(request);
      } on ServiceException catch (error) {
        final (status, code, message) = _serviceError(error.error);
        return errorResponse(status, code, message);
      } on HttpFailure catch (error) {
        return errorResponse(error.status, error.code, error.message);
      } on TimeoutException {
        return errorResponse(408, 'upload_timeout', 'Upload timed out.');
      } catch (error, stack) {
        logFailure(
          Logger('xlog.http'),
          Level.SEVERE,
          'http.failed',
          error,
          stack,
          fields: {'requestId': request.context['xlog.requestId']},
        );
        return errorResponse(
          500,
          'server_error',
          'The request could not be completed.',
        );
      }
    };

(int, String, String) _serviceError(ServiceError error) => switch (error) {
  ServiceError.queueFull => (
    429,
    'queue_full',
    'The server is busy. Try again later.',
  ),
  ServiceError.unsupportedFile => (
    415,
    'unsupported_file',
    'Choose an xlog, log, bin, or ZIP file.',
  ),
  ServiceError.uploadTooLarge => (
    413,
    'upload_too_large',
    'The upload exceeds the server limit.',
  ),
  ServiceError.emptyUpload => (
    400,
    'empty_upload',
    'The selected file is empty.',
  ),
  ServiceError.invalidFilename => (
    400,
    'invalid_filename',
    'Choose a valid file name.',
  ),
  ServiceError.jobNotFound => (
    404,
    'job_not_found',
    'Job not found or expired.',
  ),
  ServiceError.jobBusy => (
    409,
    'job_busy',
    'A running job cannot be cancelled.',
  ),
  ServiceError.resultUnavailable => (
    409,
    'result_unavailable',
    'The result is not available.',
  ),
  ServiceError.resultExpired => (
    404,
    'result_expired',
    'The result has expired.',
  ),
  ServiceError.serviceClosed => (
    503,
    'service_closed',
    'The service is shutting down.',
  ),
};
