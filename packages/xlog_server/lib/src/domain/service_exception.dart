enum ServiceError {
  queueFull,
  unsupportedFile,
  uploadTooLarge,
  emptyUpload,
  invalidFilename,
  jobNotFound,
  jobBusy,
  resultUnavailable,
  resultExpired,
  serviceClosed,
}

class ServiceException implements Exception {
  const ServiceException(this.error);

  final ServiceError error;

  @override
  String toString() => 'ServiceException(${error.name})';
}
