import "dart:convert";

import "package:flutter/cupertino.dart";
import 'package:photos/models/metadata/common_keys.dart';

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
const cameraMakeKey = 'cameraMake';
const cameraModelKey = 'cameraModel';
const motionVideoIndexKey = "mvi";
const noThumbKey = "noThumb";
const dateTimeKey = 'dateTime';
const offsetTimeKey = 'offsetTime';

String formatPubMagicDateTime(DateTime dateTime) {
  final value = dateTime.toIso8601String();
  return value.endsWith("Z") ? value.substring(0, value.length - 1) : value;
}

class MagicMetadata {
  // 0 -> visible
  // 1 -> archived
  // 2 -> hidden etc?
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
  String? cameraMake;
  String? cameraModel;

  // Indicates streaming version of the file.
  // If this is set, then the file is a streaming version of the original file.
  int? sv;

  // ISO 8601 datetime without timezone. This contains the date and time of the photo in the original tz
  // where the photo was taken.
  String? dateTime;
  String? offsetTime;

  // Motion Video Index. Positive value (>0) indicates that the file is a motion
  // photo
  int? mvi;

  // if true, then the thumbnail is not available
  // Note: desktop/web sets hasStaticThumbnail in the file metadata.
  // As we don't want to support updating the og file metadata (yet), adding
  // this new field to the pub metadata. For static thumbnail, all thumbnails
  // should have exact same hash with should match the constant `blackThumbnailBase64`
  bool? noThumb;

  // null -> not computed
  // 0 -> normal
  // 1 -> panorama
  int? mediaType;

  PubMagicMetadata({
    this.editedTime,
    this.editedName,
    this.caption,
    this.uploaderName,
    this.w,
    this.h,
    this.lat,
    this.long,
    this.cameraMake,
    this.cameraModel,
    this.mvi,
    this.noThumb,
    this.mediaType,
    this.dateTime,
    this.offsetTime,
    this.sv,
  });

  factory PubMagicMetadata.fromEncodedJson(String encodedJson) =>
      PubMagicMetadata.fromJson(jsonDecode(encodedJson));

  factory PubMagicMetadata.fromJson(dynamic json) =>
      PubMagicMetadata.fromMap(json);

  static PubMagicMetadata fromMap(Map<String, dynamic> map) {
    return PubMagicMetadata(
      editedTime: map[editTimeKey],
      editedName: map[editNameKey],
      // Some legacy remote records have been seen with numeric captions.
      caption: safeParseCaption(map[captionKey]),
      uploaderName: map[uploaderNameKey],
      w: safeParseInt(map[widthKey], widthKey),
      h: safeParseInt(map[heightKey], heightKey),
      lat: safeParseDouble(map[latKey], latKey),
      long: safeParseDouble(map[longKey], longKey),
      cameraMake: map[cameraMakeKey],
      cameraModel: map[cameraModelKey],
      mvi: map[motionVideoIndexKey],
      noThumb: map[noThumbKey],
      mediaType: map[mediaTypeKey],
      dateTime: map[dateTimeKey],
      offsetTime: map[offsetTimeKey],
      sv: safeParseInt(map[streamVersionKey], streamVersionKey),
    );
  }

  static String? safeParseCaption(dynamic value) {
    if (value == null) return null;
    if (value is String) return value;
    if (value is num) return value.toString();
    return null;
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
