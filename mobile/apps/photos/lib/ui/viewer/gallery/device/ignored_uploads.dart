import "package:flutter/widgets.dart";
import "package:photos/core/configuration.dart";
import "package:photos/core/constants.dart";
import "package:photos/db/device_files_db.dart";
import "package:photos/db/files_db.dart";
import "package:photos/generated/l10n.dart";
import "package:photos/models/device_collection.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/ignored_upload_reason.dart";
import "package:photos/services/ignored_files_service.dart";

Future<List<EnteFile>> filesInDeviceCollectionFor(
  DeviceCollection deviceCollection,
) async {
  return (await FilesDB.instance.getFilesInDeviceCollection(
    deviceCollection,
    Configuration.instance.getUserID(),
    galleryLoadStartTime,
    galleryLoadEndTime,
  )).files;
}

Future<Set<IgnoredUploadReasonBucket>> ignoredUploadReasonBuckets(
  Future<List<EnteFile>> filesInDeviceCollection,
) async {
  final deviceCollectionFiles = await filesInDeviceCollection;
  final allIgnoredIDs = await IgnoredFilesService.instance.idToIgnoreReasonMap;
  final buckets = <IgnoredUploadReasonBucket>{};
  for (final file in deviceCollectionFiles) {
    final bucket = ignoredUploadReasonBucketForFile(allIgnoredIDs, file);
    if (bucket != null) {
      buckets.add(bucket);
    }
  }
  return buckets;
}

List<IgnoredUploadReasonBucket> visibleIgnoredUploadBuckets(
  Set<IgnoredUploadReasonBucket> availableBuckets,
) {
  return [
    IgnoredUploadReasonBucket.deletedFromEnte,
    IgnoredUploadReasonBucket.iCloudUnavailable,
    IgnoredUploadReasonBucket.other,
  ].where(availableBuckets.contains).toList();
}

IgnoredUploadReasonBucket? ignoredUploadReasonBucketForFile(
  Map<String, String> idToReasonMap,
  EnteFile file,
) {
  final reason = IgnoredFilesService.instance.getUploadSkipReason(
    idToReasonMap,
    file,
  );
  return reason == null ? null : ignoredUploadReasonBucketFor(reason);
}

String ignoredUploadReasonBucketLabel(
  BuildContext context,
  IgnoredUploadReasonBucket bucket,
) {
  final l10n = AppLocalizations.of(context);
  return switch (bucket) {
    IgnoredUploadReasonBucket.iCloudUnavailable => l10n.iCloudUnavailable,
    IgnoredUploadReasonBucket.deletedFromEnte => l10n.deletedFromEnte,
    IgnoredUploadReasonBucket.other => l10n.others,
  };
}
