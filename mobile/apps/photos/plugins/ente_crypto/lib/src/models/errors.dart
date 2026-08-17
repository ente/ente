class KeyDerivationError extends Error {}

class LoginKeyDerivationError extends Error {}

class StreamPullErr implements Exception {
  final String message;
  final dynamic originalException;

  StreamPullErr(this.message, [this.originalException]);

  @override
  String toString() {
    if (originalException != null) {
      return 'StreamPullErr: $message\nCaused by: $originalException';
    }
    return 'StreamPullErr: $message';
  }
}

extension FutureErrorHandling<T> on Future<T> {
  Future<T> unwrapExceptionInComputer() {
    return catchError((e) {
      final msg = e.toString();
      if (msg.contains(kPartialReadErrorTag)) {
        throw PartialReadException(msg);
      }
      if (msg.contains(kVerificationErrorTag)) {
        final parts = msg.split(kVerificationErrorTag + ':');
        final errorMessage = parts.length > 1 ? parts[1].trim() : msg;
        throw VerificationError(errorMessage);
      }
      throw e;
    });
  }
}

const kPartialReadErrorTag = 'PartialRead';
const kStreamPullError = 'crypto_secretstream_xchacha20poly1305_pull';
const kVerificationErrorTag = 'VerificationError';
const kBitFlipErrorTag = 'BitFlipDetected';

class PartialReadException implements Exception {
  final String message;
  PartialReadException(this.message);

  @override
  String toString() => 'PartialReadException: $message';
}

class VerificationError implements Exception {
  final String message;
  final dynamic originalException;

  VerificationError(this.message, [this.originalException]);

  @override
  String toString() {
    if (originalException != null) {
      return 'VerificationError: $message\nCaused by: $originalException';
    }
    return 'VerificationError: $message';
  }
}

class BitFlipError implements Exception {
  final String message;
  BitFlipError(this.message);

  @override
  String toString() => 'BitFlipError: $message';
}
