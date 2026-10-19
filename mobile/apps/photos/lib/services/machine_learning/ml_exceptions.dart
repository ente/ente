import "package:photos/core/exceptions.dart";

class ModelDownloadNetworkException implements Exception, LocallyHandledError {
  const ModelDownloadNetworkException(this.message);

  final String message;

  @override
  String toString() => "ModelDownloadNetworkException: $message";
}

class ThumbnailRetrievalException implements Exception {
  final String message;
  final StackTrace stackTrace;

  ThumbnailRetrievalException(this.message, this.stackTrace);

  @override
  String toString() {
    return 'ThumbnailRetrievalException: $message\n$stackTrace';
  }
}

class CouldNotRetrieveAnyFileData implements Exception, LocallyHandledError {}

class RepeatedFileDecryptionError implements Exception, LocallyHandledError {}
