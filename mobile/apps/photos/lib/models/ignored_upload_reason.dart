import "package:photos/models/ignored_file.dart";
import "package:photos/utils/apple_photos_errors.dart";

enum IgnoredUploadReasonBucket { iCloudUnavailable, deletedFromEnte, other }

IgnoredUploadReasonBucket ignoredUploadReasonBucketFor(String reason) {
  if (reason == phPhotosResourceUnavailableReason) {
    return IgnoredUploadReasonBucket.iCloudUnavailable;
  }
  if (reason == kIgnoreReasonTrash) {
    return IgnoredUploadReasonBucket.deletedFromEnte;
  }
  return IgnoredUploadReasonBucket.other;
}
