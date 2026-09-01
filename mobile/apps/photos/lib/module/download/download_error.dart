class DownloadFailedError implements Exception {
  final String message;

  DownloadFailedError(this.message);

  @override
  String toString() => message;
}

class DownloadNoConnectionError extends DownloadFailedError {
  DownloadNoConnectionError() : super('No connection');
}

class DownloadUnavailableError extends DownloadFailedError {
  DownloadUnavailableError() : super('Unavailable');
}

class DownloadDecryptionFailedError extends DownloadFailedError {
  DownloadDecryptionFailedError() : super('Failed to decrypt downloaded file');
}

Future<T?> handleDownloadDecryptionFailureForCaller<T>(
  Future<T?> download, {
  required bool rethrowDecryptionFailure,
}) async {
  try {
    return await download;
  } on DownloadDecryptionFailedError {
    if (rethrowDecryptionFailure) {
      rethrow;
    }
    return null;
  }
}
