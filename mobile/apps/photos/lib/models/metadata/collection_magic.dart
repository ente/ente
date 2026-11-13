import 'dart:convert';

import "package:photos/models/metadata/common_keys.dart";

const subTypeDefaultHidden = 1;
const subTypeSharedFilesCollection = 2;

const subTypeKey = 'subType';

const muteKey = "mute";

const orderKey = "order";

const albumDescriptionKey = "caption";
const maxAlbumDescriptionLength = 200;

class CollectionMagicMetadata {
  // 0 = visible, 1 = archived, 2 = hidden.
  int visibility;

  // null/0 = none; other values use the subType constants above.
  int? subType;

  // Higher values give a collection higher display priority.
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
  bool? asc;

  int? coverID;

  // layout for public link sharing (masonry, grouped, continuous, trip)
  String? layout;

  String? description;

  CollectionPubMagicMetadata({
    this.asc,
    this.coverID,
    this.layout,
    this.description,
  });

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> result = {"asc": asc ?? false};
    if (coverID != null) {
      result["coverID"] = coverID!;
    }
    if (layout != null) {
      result["layout"] = layout!;
    }
    if (description != null) {
      result[albumDescriptionKey] = description!;
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
      description: map[albumDescriptionKey] as String?,
    );
  }
}

class ShareeMagicMetadata {
  // 0 = visible, 1 = archived, 2 = hidden.
  int visibility;

  bool? mute;

  // Higher values give a collection higher display priority.
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
