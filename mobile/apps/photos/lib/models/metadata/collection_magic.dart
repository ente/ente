import 'dart:convert';

import "package:photos/models/metadata/common_keys.dart";

// Collection SubType Constants
const subTypeDefaultHidden = 1;
const subTypeSharedFilesCollection = 2;

// key for collection subType
const subTypeKey = 'subType';

const muteKey = "mute";

const orderKey = "order";

class CollectionMagicMetadata {
  // 0 -> visible
  // 1 -> archived
  // 2 -> hidden
  int visibility;

  // null/0 value -> no subType
  // 1 -> DEFAULT_HIDDEN COLLECTION for files hidden individually
  // 2 -> Collections created for sharing selected files
  int? subType;

  /* order is initially just used for pinned collections.
  Later it can be used for custom sort order for if needed.
  Higher the value, higher the preference of the collection to show up first.
  */
  int? order;

  CollectionMagicMetadata({required this.visibility, this.subType, this.order});

  Map<String, dynamic> toJson() {
    final result = {magicKeyVisibility: visibility};
    if (subType != null) {
      result[subTypeKey] = subType!;
    }
    if (order != null) {
      result[orderKey] = order!;
    }
    return result;
  }

  factory CollectionMagicMetadata.fromEncodedJson(String encodedJson) =>
      CollectionMagicMetadata.fromJson(jsonDecode(encodedJson));

  factory CollectionMagicMetadata.fromJson(dynamic json) =>
      CollectionMagicMetadata.fromMap(json);

  static CollectionMagicMetadata fromMap(Map<String, dynamic> map) {
    return CollectionMagicMetadata(
      visibility: map[magicKeyVisibility] ?? visibleVisibility,
      subType: map[subTypeKey],
      order: map[orderKey],
    );
  }
}

class CollectionPubMagicMetadata {
  // sort order while showing collection
  bool? asc;

  // cover photo id for the collection
  int? coverID;

  // layout for public link sharing (masonry, grouped, continuous, trip)
  String? layout;

  CollectionPubMagicMetadata({this.asc, this.coverID, this.layout});

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> result = {"asc": asc ?? false};
    if (coverID != null) {
      result["coverID"] = coverID!;
    }
    if (layout != null) {
      result["layout"] = layout!;
    }
    return result;
  }

  factory CollectionPubMagicMetadata.fromEncodedJson(String encodedJson) =>
      CollectionPubMagicMetadata.fromJson(jsonDecode(encodedJson));

  factory CollectionPubMagicMetadata.fromJson(dynamic json) =>
      CollectionPubMagicMetadata.fromMap(json);

  static CollectionPubMagicMetadata fromMap(Map<String, dynamic> map) {
    return CollectionPubMagicMetadata(
      asc: map["asc"] as bool?,
      coverID: map["coverID"],
      layout: map["layout"] as String? ?? "masonry",
    );
  }
}

class ShareeMagicMetadata {
  // 0 -> visible
  // 1 -> archived
  // 2 -> hidden etc?
  int visibility;

  // null/false value -> no mute
  bool? mute;

  /* order is used for pinned collections for sharees.
  Higher the value, higher the preference of the collection to show up first.
  */
  int? order;

  ShareeMagicMetadata({required this.visibility, this.mute, this.order});

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> result = {magicKeyVisibility: visibility};
    if (mute != null) {
      result[muteKey] = mute!;
    }
    if (order != null) {
      result[orderKey] = order!;
    }
    return result;
  }

  factory ShareeMagicMetadata.fromEncodedJson(String encodedJson) =>
      ShareeMagicMetadata.fromJson(jsonDecode(encodedJson));

  factory ShareeMagicMetadata.fromJson(dynamic json) =>
      ShareeMagicMetadata.fromMap(json);

  static ShareeMagicMetadata fromMap(Map<String, dynamic> map) {
    return ShareeMagicMetadata(
      visibility: map[magicKeyVisibility] ?? visibleVisibility,
      mute: map[muteKey],
      order: map[orderKey],
    );
  }
}
