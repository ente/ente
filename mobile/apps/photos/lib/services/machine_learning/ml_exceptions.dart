import "package:photos/core/exceptions.dart";

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
