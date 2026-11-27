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

class RustCorruptModelException implements Exception {
  const RustCorruptModelException(this.modelPath);

  final String modelPath;

  @override
  String toString() => "RustCorruptModelException: $modelPath";
}

class InvalidImageFormatException implements Exception {
  const InvalidImageFormatException(this.message);

  final String message;

  @override
  String toString() => "InvalidImageFormatException: $message";
}

class FileTooLargeForMLException implements Exception {
  const FileTooLargeForMLException(this.fileSize);

  final int fileSize;

  @override
  String toString() => "FileTooLargeForMLException: size is $fileSize";
}
