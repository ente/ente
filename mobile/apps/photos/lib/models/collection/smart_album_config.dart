typedef PersonInfo = ({int updatedAt, Set<int> addedFiles});

class SmartAlbumConfig {
  // A nullable remote ID for syncing purposes
  final String? id;

  final int collectionId;
  // person ids
  final Set<String> personIDs;
  // person id mapped with updatedat, file ids
  final Map<String, PersonInfo> infoMap;
  final int updatedAt;

  SmartAlbumConfig({
    this.id,
    required this.collectionId,
    required this.personIDs,
    required this.infoMap,
    this.updatedAt = 0,
  });

  SmartAlbumConfig getUpdatedConfig(Set<String> newPersonsIds) {
    final toAdd = newPersonsIds.difference(personIDs);
    final toRemove = personIDs.difference(newPersonsIds);
    final newInfoMap = Map<String, PersonInfo>.from(infoMap);

    // Remove whats not needed
    for (final personId in toRemove) {
      newInfoMap.remove(personId);
    }

    // Add files which are needed
    for (final personId in toAdd) {
      newInfoMap[personId] = (updatedAt: 0, addedFiles: <int>{});
    }

    return SmartAlbumConfig(
      id: id,
      collectionId: collectionId,
      personIDs: newPersonsIds,
      infoMap: newInfoMap,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
  }

  SmartAlbumConfig addFiles(
    Map<String, int> personUpdatedAt,
    Map<String, Set<int>> personMappedFiles,
  ) {
    final newInfoMap = Map<String, PersonInfo>.from(infoMap);
    var isUpdated = false;

    personMappedFiles.forEach((personId, fileIds) {
      if (newInfoMap.containsKey(personId)) {
        isUpdated = true;
        newInfoMap[personId] = (
          updatedAt:
              personUpdatedAt[personId] ??
              DateTime.now().millisecondsSinceEpoch,
          addedFiles: {...?newInfoMap[personId]?.addedFiles, ...fileIds},
        );
      }
    });

    if (!isUpdated) return this;

    return SmartAlbumConfig(
      id: id,
      collectionId: collectionId,
      personIDs: personIDs,
      infoMap: newInfoMap,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
  }

  // toJson and fromJson methods
  Map<String, dynamic> toJson() {
    return {
      "collection_id": collectionId,
      "person_ids": personIDs.toList(),
      "info_map": infoMap.map(
        (key, value) => MapEntry(key, {
          "updated_at": value.updatedAt,
          "added_files": value.addedFiles.toList(),
        }),
      ),
    };
  }

  factory SmartAlbumConfig.fromJson(
    Map<String, dynamic> json,
    String id,
    int updatedAt,
  ) {
    final personIDs = Set<String>.from(json["person_ids"] as List? ?? []);
    final infoMap = (json["info_map"] as Map<String, dynamic>).map(
      (key, value) => MapEntry(key, (
        updatedAt:
            value["updated_at"] as int? ??
            DateTime.now().millisecondsSinceEpoch,
        addedFiles: Set<int>.from(value["added_files"] as List? ?? []),
      )),
    );

    return SmartAlbumConfig(
      id: id,
      collectionId: json["collection_id"] as int,
      personIDs: personIDs,
      infoMap: infoMap,
      updatedAt: updatedAt,
    );
  }
}
