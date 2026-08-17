import "dart:convert";

import "package:flutter/cupertino.dart";
import "package:locker/services/files/sync/models/common_keys.dart";

const editTimeKey = 'editedTime';
const editNameKey = 'editedName';
const captionKey = "caption";
const uploaderNameKey = "uploaderName";
const widthKey = 'w';
const heightKey = 'h';
const streamVersionKey = 'sv';
const mediaTypeKey = 'mediaType';
const latKey = "lat";
const longKey = "long";
const motionVideoIndexKey = "mvi";
const noThumbKey = "noThumb";
const dateTimeKey = 'dateTime';
const offsetTimeKey = 'offsetTime';
const infoKey = 'info';

class MagicMetadata {
  // 0 = visible, 1 = archived, 2 = hidden.
  int visibility;

  MagicMetadata({required this.visibility});

  factory MagicMetadata.fromEncodedJson(String encodedJson) =>
      MagicMetadata.fromJson(jsonDecode(encodedJson));

  factory MagicMetadata.fromJson(dynamic json) => MagicMetadata.fromMap(json);

  static MagicMetadata fromMap(Map<String, dynamic> map) {
    return MagicMetadata(
      visibility: map[magicKeyVisibility] ?? visibleVisibility,
    );
  }
}

class PubMagicMetadata {
  int? editedTime;
  String? editedName;
  String? caption;
  String? uploaderName;
  int? w;
  int? h;
  double? lat;
  double? long;

  // If this is set, then the file is a streaming version of the original file.
  int? sv;

  // ISO 8601 datetime without an offset, using the photo's original timezone.
  String? dateTime;
  String? offsetTime;

  // A positive Motion Video Index marks a motion photo.
  int? mvi;

  // Mobile stores missing-thumbnail state in public metadata. Desktop and web
  // use hasStaticThumbnail in file metadata. Missing thumbnails use
  // blackThumbnailBase64.
  bool? noThumb;

  // null = unknown, 0 = normal, 1 = panorama.
  int? mediaType;

  // Locker writes camelCase info type names in this JSON.
  Map<String, dynamic>? info;

  PubMagicMetadata({
    this.editedTime,
    this.editedName,
    this.caption,
    this.uploaderName,
    this.w,
    this.h,
    this.lat,
    this.long,
    this.mvi,
    this.noThumb,
    this.mediaType,
    this.dateTime,
    this.offsetTime,
    this.sv,
    this.info,
  });

  factory PubMagicMetadata.fromEncodedJson(String encodedJson) =>
      PubMagicMetadata.fromJson(jsonDecode(encodedJson));

  factory PubMagicMetadata.fromJson(dynamic json) =>
      PubMagicMetadata.fromMap(json);

  static PubMagicMetadata fromMap(Map<String, dynamic> map) {
    return PubMagicMetadata(
      editedTime: map[editTimeKey],
      editedName: map[editNameKey],
      caption: map[captionKey],
      uploaderName: map[uploaderNameKey],
      w: safeParseInt(map[widthKey], widthKey),
      h: safeParseInt(map[heightKey], heightKey),
      lat: safeParseDouble(map[latKey], latKey),
      long: safeParseDouble(map[longKey], longKey),
      mvi: map[motionVideoIndexKey],
      noThumb: map[noThumbKey],
      mediaType: map[mediaTypeKey],
      dateTime: map[dateTimeKey],
      offsetTime: map[offsetTimeKey],
      sv: safeParseInt(map[streamVersionKey], streamVersionKey),
      info: map[infoKey],
    );
  }

  static int? safeParseInt(dynamic value, String key) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is String) return int.tryParse(value);
    debugPrint("PubMagicMetadata key: $key Unexpected value: $value");
    return null;
  }

  static double? safeParseDouble(dynamic value, String key) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    debugPrint("PubMagicMetadata key: $key Unexpected value: $value");
    return null;
  }
}
