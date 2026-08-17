class InvalidFileError extends ArgumentError {
  InvalidFileError(String super.message);
}

class InvalidFileUploadState extends AssertionError {
  InvalidFileUploadState(String super.message);
}

class SubscriptionAlreadyClaimedError extends Error {}

class WiFiUnavailableError extends Error {}

class SyncStopRequestedError extends Error {}

class NoActiveSubscriptionError extends Error {}

class StorageLimitExceededError extends Error {}

class FileTooLargeForPlanError extends Error {}

class SilentlyCancelUploadsError extends Error {}

class UserCancelledUploadError extends Error {}

class LockAlreadyAcquiredError extends Error {}

class UnauthorizedError extends Error {}

class RequestCancelledError extends Error {}

class InvalidSyncStatusError extends AssertionError {
  InvalidSyncStatusError(String super.message);
}

class UnauthorizedEditError extends AssertionError {}

class InvalidStateError extends AssertionError {
  InvalidStateError(String super.message);
}

class SrpSetupNotCompleteError extends Error {}

class AuthenticatorKeyNotFound extends Error {}

class PassKeySessionNotVerifiedError extends Error {}

class PassKeySessionExpiredError extends Error {}
