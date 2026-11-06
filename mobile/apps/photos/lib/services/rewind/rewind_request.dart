import "package:collection/collection.dart";
import "package:flutter_rust_bridge/flutter_rust_bridge.dart" show Int64List;
import "package:package_info_plus/package_info_plus.dart";
import "package:photos/core/configuration.dart";
import "package:photos/db/files_db.dart";
import "package:photos/db/social_db.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/file/file_type.dart";
import "package:photos/models/metadata/common_keys.dart";
import "package:photos/models/ml/face/person.dart";
import "package:photos/models/social/reaction.dart";
import "package:photos/service_locator.dart";
import "package:photos/services/collections_service.dart";
import "package:photos/services/favorites_service.dart";
import "package:photos/services/machine_learning/face_ml/person/person_service.dart";
import "package:photos/services/memories/memory_sources.dart";
import "package:photos/services/rewind/rewind_edition.dart";
import "package:photos/src/rust/api/rewind_api.dart" as rust;

bool get rewindUsesMl =>
    hasGrantedMLConsent && localSettings.isMLLocalIndexingEnabled;

const _screenshotName = "screenshot";
const _reactionPageSize = 1000;

Future<rust.RewindRequest> buildRewindRequest(DateTime now) async {
  final packageInfo = await PackageInfo.fromPlatform();
  final persons = isLocalGalleryMode || !rewindUsesMl
      ? const <PersonEntity>[]
      : await PersonService.instance.getPersons();
  final email = isLocalGalleryMode ? null : Configuration.instance.getEmail();
  return rust.RewindRequest(
    year: RewindEdition.year,
    now: now.microsecondsSinceEpoch,
    utcOffsetSeconds: now.timeZoneOffset.inSeconds,
    seasonStart: RewindEdition.availableFrom.microsecondsSinceEpoch,
    installedAt: packageInfo.installTime?.microsecondsSinceEpoch ?? 0,
    localGalleryMode: isLocalGalleryMode,
    files: isLocalGalleryMode ? await _localFiles() : await _ownedFiles(),
    people: [
      for (final person in persons)
        rust.RewindPerson(
          id: person.remoteID,
          isIgnored: person.data.isIgnored,
          isHiddenFromMemories: person.data.hideFromMemories,
        ),
    ],
    mePersonId: email == null
        ? null
        : persons
              .firstWhereOrNull((person) => person.data.email == email)
              ?.remoteID,
  );
}

Future<List<rust.RewindFile>> _localFiles() async {
  final files = await getFilesAndMapForMemories(
    useLocalIntIds: true,
    requireLocalId: true,
  );
  return [
    for (final MapEntry(key: id, value: file) in files.entries)
      _rewindFile(
        id,
        file,
        visibility: rust.RewindVisibility.visible,
        isFavourite: false,
        isJunk: _isScreenshotName(file.deviceFolder),
        isScreenshot: _isScreenshotName(file.deviceFolder),
        sharedAlbumIds: const [],
        likeCount: 0,
      ),
  ];
}

Future<List<rust.RewindFile>> _ownedFiles() async {
  final userID = Configuration.instance.getUserID();
  if (userID == null) return const [];
  final rows = await FilesDB.instance.getAllFilesFromDB(
    const {},
    dedupeByUploadId: false,
  );
  final files = <int, EnteFile>{};
  final collectionIDs = <int, Set<int>>{};
  for (final row in rows) {
    final id = row.uploadedFileID;
    if (id == null ||
        id == -1 ||
        row.ownerID != userID ||
        row.creationTime == null) {
      continue;
    }
    files.putIfAbsent(id, () => row);
    final collectionID = row.collectionID;
    if (collectionID != null) {
      collectionIDs.putIfAbsent(id, () => {}).add(collectionID);
    }
  }
  final albums = await _Albums.load(userID);
  final likeCounts = await _likeCounts(userID);
  return [
    for (final MapEntry(key: id, value: file) in files.entries)
      _ownedFile(
        id,
        file,
        collectionIDs[id] ?? const {},
        albums,
        likeCounts[id] ?? 0,
      ),
  ];
}

rust.RewindFile _ownedFile(
  int id,
  EnteFile file,
  Set<int> collectionIDs,
  _Albums albums,
  int likeCount,
) {
  return _rewindFile(
    id,
    file,
    visibility: albums.visibility(file, collectionIDs),
    isFavourite: collectionIDs.contains(albums.favourites),
    isJunk: collectionIDs.any(albums.junk.contains),
    isScreenshot: collectionIDs.any(albums.screenshots.contains),
    sharedAlbumIds: collectionIDs.where(albums.shared.contains).toList(),
    likeCount: likeCount,
  );
}

rust.RewindFile _rewindFile(
  int id,
  EnteFile file, {
  required rust.RewindVisibility visibility,
  required bool isFavourite,
  required bool isJunk,
  required bool isScreenshot,
  required List<int> sharedAlbumIds,
  required int likeCount,
}) {
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
    location: _location(file),
    visibility: visibility,
    isFavourite: isFavourite,
    isJunk: isJunk,
    isScreenshot: isScreenshot,
    sharedAlbumIds: Int64List.fromList(sharedAlbumIds),
    likeCount: likeCount,
  );
}

rust.RewindLocation? _location(EnteFile file) {
  final latitude = file.location?.latitude;
  final longitude = file.location?.longitude;
  if (!file.hasLocation || latitude == null || longitude == null) return null;
  return rust.RewindLocation(latitude: latitude, longitude: longitude);
}

bool _isScreenshotName(String? name) =>
    name?.toLowerCase().contains(_screenshotName) ?? false;

Future<Map<int, int>> _likeCounts(int ownerID) async {
  final likers = <int, Set<String>>{};
  var offset = 0;
  List<Reaction> page;
  do {
    page = await SocialDB.instance.getReactionsOnFiles(
      excludeUserID: ownerID,
      limit: _reactionPageSize,
      offset: offset,
    );
    for (final reaction in page) {
      final fileID = reaction.fileID;
      if (fileID == null) continue;
      likers
          .putIfAbsent(fileID, () => {})
          .add(
            reaction.isAnonymous
                ? "anonymous:${reaction.anonUserID}"
                : "user:${reaction.userID}",
          );
    }
    offset += page.length;
  } while (page.length == _reactionPageSize);
  return {
    for (final MapEntry(key: fileID, value: people) in likers.entries)
      fileID: people.length,
  };
}

class _Albums {
  _Albums({
    required this.hidden,
    required this.archived,
    required this.junk,
    required this.screenshots,
    required this.shared,
    required this.favourites,
  });

  final Set<int> hidden;
  final Set<int> archived;
  final Set<int> junk;
  final Set<int> screenshots;
  final Set<int> shared;
  final int? favourites;

  static Future<_Albums> load(int userID) async {
    final collections = CollectionsService.instance;
    final hidden = collections.getHiddenCollectionIds();
    final archivedOrHidden = collections.archivedOrHiddenCollectionIds();
    return _Albums(
      hidden: hidden,
      archived: archivedOrHidden.difference(hidden),
      junk: (await getCollectionIDsToExclude()).difference(archivedOrHidden),
      screenshots: {
        for (final collection in collections.getCollectionsForUI())
          if (_isScreenshotName(collection.displayName)) collection.id,
      },
      shared: {
        for (final collection in collections.getActiveCollections())
          if (!collection.isHidden() &&
              (collection.hasSharees ||
                  collection.hasLink ||
                  !collection.isOwner(userID)))
            collection.id,
      },
      favourites:
          (await FavoritesService.instance.getFavoritesCollection())?.id,
    );
  }

  rust.RewindVisibility visibility(EnteFile file, Set<int> collectionIDs) {
    final fileVisibility = file.magicMetadata.visibility;
    if (fileVisibility == hiddenVisibility ||
        collectionIDs.any(hidden.contains)) {
      return rust.RewindVisibility.hidden;
    }
    if (fileVisibility == archiveVisibility ||
        collectionIDs.any(archived.contains)) {
      return rust.RewindVisibility.archived;
    }
    return rust.RewindVisibility.visible;
  }
}
