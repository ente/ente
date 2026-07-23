import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';

/// Used to store the display settings of a code.
class CodeDisplay {
  final bool pinned;
  final bool trashed;
  final int lastUsedAt;
  final int tapCount;
  String note;
  final List<String> tags;
  int position;
  String iconSrc;
  String iconID;

  CodeDisplay({
    this.pinned = false,
    this.trashed = false,
    this.lastUsedAt = 0,
    this.tapCount = 0,
    this.tags = const [],
    this.note = '',
    this.position = 0,
    this.iconSrc = '',
    this.iconID = '',
  });

  bool get isCustomIcon => (iconSrc != '' && iconID != '');

  // copyWith
  CodeDisplay copyWith({
    bool? pinned,
    bool? trashed,
    int? lastUsedAt,
    int? tapCount,
    List<String>? tags,
    String? note,
    int? position,
    String? iconSrc,
    String? iconID,
  }) {
    final bool updatedPinned = pinned ?? this.pinned;
    final bool updatedTrashed = trashed ?? this.trashed;
    final int updatedLastUsedAt = lastUsedAt ?? this.lastUsedAt;
    final int updatedTapCount = tapCount ?? this.tapCount;
    final List<String> updatedTags = tags ?? this.tags;
    final String updatedNote = note ?? this.note;
    final int updatedPosition = position ?? this.position;
    final String updatedIconSrc = iconSrc ?? this.iconSrc;
    final String updatedIconID = iconID ?? this.iconID;

    return CodeDisplay(
      pinned: updatedPinned,
      trashed: updatedTrashed,
      lastUsedAt: updatedLastUsedAt,
      tapCount: updatedTapCount,
      tags: updatedTags,
      note: updatedNote,
      position: updatedPosition,
      iconSrc: updatedIconSrc,
      iconID: updatedIconID,
    );
  }

  factory CodeDisplay.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return CodeDisplay();
    }
    return CodeDisplay(
      pinned: json['pinned'] ?? false,
      trashed: json['trashed'] ?? false,
      lastUsedAt: json['lastUsedAt'] ?? 0,
      tapCount: json['tapCount'] ?? 0,
      tags: List<String>.from(json['tags'] ?? []),
      note: json['note'] ?? '',
      position: json['position'] ?? 0,
      iconSrc: json['iconSrc'] ?? 'ente',
      iconID: json['iconID'] ?? '',
    );
  }

  /// Converts the [CodeDisplay] to a json object.
  /// When [safeParsing] is true, the json will be parsed safely.
  /// If we fail to parse the json, we will return an empty [CodeDisplay].
  static CodeDisplay? fromUri(Uri uri, {bool safeParsing = false}) {
    if (!uri.queryParameters.containsKey("codeDisplay")) return null;
    final String codeDisplay = uri.queryParameters['codeDisplay']!.replaceAll(
      '%2C',
      ',',
    );
    return _parseCodeDisplayJson(codeDisplay, safeParsing);
  }

  static CodeDisplay _parseCodeDisplayJson(String json, bool safeParsing) {
    try {
      final decodedDisplay = jsonDecode(json);
      return CodeDisplay.fromJson(decodedDisplay);
    } catch (e, s) {
      Logger(
        "CodeDisplay",
      ).severe("Could not parse code display from json", e, s);
      // (ng/prateek) Handle the case where we have fragment in the rawDataUrl
      if (!json.endsWith("}") && json.contains("}#")) {
        Logger("CodeDisplay").warning("ignoring code display as it's invalid");
        return CodeDisplay();
      }
      if (safeParsing) {
        return CodeDisplay();
      } else {
        rethrow;
      }
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'pinned': pinned,
      'trashed': trashed,
      'lastUsedAt': lastUsedAt,
      'tapCount': tapCount,
      'tags': tags,
      'note': note,
      'position': position,
      'iconSrc': iconSrc,
      'iconID': iconID,
    };
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is CodeDisplay &&
        other.pinned == pinned &&
        other.trashed == trashed &&
        other.lastUsedAt == lastUsedAt &&
        other.tapCount == tapCount &&
        other.note == note &&
        listEquals(other.tags, tags);
  }

  @override
  int get hashCode {
    return pinned.hashCode ^
        trashed.hashCode ^
        lastUsedAt.hashCode ^
        tapCount.hashCode ^
        note.hashCode ^
        tags.hashCode;
  }
}
