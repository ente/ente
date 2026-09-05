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

class DownloadDecryptionError extends DownloadFailedError {
  final String encryptedFileSha1;

  DownloadDecryptionError(this.encryptedFileSha1)
    : super('Failed to decrypt downloaded file');
}

Future<T?> handleDownloadDecryptionFailureForCaller<T>(
  Future<T?> download, {
  required bool rethrowDecryptionFailure,
}) async {
  try {
    return await download;
  } on DownloadDecryptionError {
    if (rethrowDecryptionFailure) {
      rethrow;
    }
    return null;
  }
}
