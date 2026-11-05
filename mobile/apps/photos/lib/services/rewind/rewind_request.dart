import "package:package_info_plus/package_info_plus.dart";
import "package:photos/core/configuration.dart";
import "package:photos/db/files_db.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/file/file_type.dart";
import "package:photos/service_locator.dart";
import "package:photos/services/memories/memory_sources.dart";
import "package:photos/services/rewind/rewind_edition.dart";
import "package:photos/src/rust/api/rewind_api.dart" as rust;

bool get rewindUsesMl =>
    hasGrantedMLConsent && localSettings.isMLLocalIndexingEnabled;

Future<rust.RewindRequest> buildRewindRequest(DateTime now) async {
  final files = isLocalGalleryMode
      ? await getFilesAndMapForMemories(
          useLocalIntIds: true,
          requireLocalId: true,
        )
      : await _ownedUploadedFiles();
  final packageInfo = await PackageInfo.fromPlatform();
  return rust.RewindRequest(
    year: RewindEdition.year,
    now: now.microsecondsSinceEpoch,
    utcOffsetSeconds: now.timeZoneOffset.inSeconds,
    seasonStart: RewindEdition.availableFrom.microsecondsSinceEpoch,
    installedAt: packageInfo.installTime?.microsecondsSinceEpoch ?? 0,
    localGalleryMode: isLocalGalleryMode,
    files: [
      for (final entry in files.entries) _rewindFile(entry.key, entry.value),
    ],
  );
}

Future<Map<int, EnteFile>> _ownedUploadedFiles() async {
  final userID = Configuration.instance.getUserID();
  final files = await FilesDB.instance.getAllFilesFromDB(const {});
  final owned = <int, EnteFile>{};
  for (final file in files) {
    final id = file.uploadedFileID;
    if (id == null ||
        id == -1 ||
        file.ownerID != userID ||
        file.creationTime == null) {
      continue;
    }
    owned.putIfAbsent(id, () => file);
  }
  return owned;
}

rust.RewindFile _rewindFile(int id, EnteFile file) {
  final creationTime = file.creationTime!;
  return rust.RewindFile(
    id: id,
    creationTime: creationTime,
    localDateTime: file.pubMagicMetadata?.dateTime,
    utcOffsetSeconds: DateTime.fromMicrosecondsSinceEpoch(
      creationTime,
    ).timeZoneOffset.inSeconds,
    fileType: switch (file.fileType) {
      FileType.image => rust.RewindFileType.image,
      FileType.video => rust.RewindFileType.video,
      FileType.livePhoto => rust.RewindFileType.livePhoto,
      FileType.other => rust.RewindFileType.other,
    },
  );
}
