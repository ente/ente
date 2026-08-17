class UnauthorizedError extends Error {}

class PassKeySessionNotVerifiedError extends Error {}

class PassKeySessionExpiredError extends Error {}

class SrpSetupNotCompleteError extends Error {}

class StorageLimitExceededError extends Error {}

class NoActiveSubscriptionError extends Error {}

class FileLimitReachedError extends Error {}

class FileTooLargeForPlanError extends Error {}

class WiFiUnavailableError extends Error {}

class SilentlyCancelUploadsError extends Error {}

class SharingNotPermittedForFreeAccountsError extends Error {}

class InvalidFileError extends ArgumentError {
  final InvalidReason reason;

  InvalidFileError(String super.message, this.reason);

  @override
  String toString() {
    return 'InvalidFileError: $message (reason: $reason)';
  }
}

enum InvalidReason {
  assetDeleted,
  assetDeletedEvent,
  sourceFileMissing,
  livePhotoToImageTypeChanged,
  imageToLivePhotoTypeChanged,
  livePhotoVideoMissing,
  thumbnailMissing,
  tooLargeFile,
  unknown,
}
