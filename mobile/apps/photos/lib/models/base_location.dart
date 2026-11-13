import "dart:convert";

import "package:photos/models/location/location.dart";

const baseRadius = 0.6;

class BaseLocation {
  final List<int> fileIDs;
  int? firstCreationTime;
  int? lastCreationTime;
  final Location location;
  final bool isCurrentBase;

  BaseLocation(
    this.fileIDs,
    this.location,
    this.isCurrentBase, {
    this.firstCreationTime,
    this.lastCreationTime,
  });

  static List<BaseLocation> decodeJsonToList(String jsonString) {
    final jsonList = jsonDecode(jsonString) as List;
    return jsonList.map((json) => BaseLocation.fromJson(json)).toList();
  }

  static String encodeListToJson(List<BaseLocation> baseLocations) {
    final jsonList = baseLocations
        .map((location) => location.toJson())
        .toList();
    return jsonEncode(jsonList);
  }

  static BaseLocation fromJson(Map<String, dynamic> json) {
    return BaseLocation(
      (json['fileIDs'] as List).cast<int>(),
      Location(
        latitude: json['location']['latitude'],
        longitude: json['location']['longitude'],
      ),
      json['isCurrentBase'] as bool,
      firstCreationTime: json['firstCreationTime'] as int?,
      lastCreationTime: json['lastCreationTime'] as int?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'fileIDs': fileIDs,
      'location': {
        'latitude': location.latitude!,
        'longitude': location.longitude!,
      },
      'isCurrentBase': isCurrentBase,
      'firstCreationTime': firstCreationTime,
      'lastCreationTime': lastCreationTime,
    };
  }

  BaseLocation copyWith({
    List<int>? files,
    int? firstCreationTime,
    int? lastCreationTime,
    Location? location,
    bool? isCurrentBase,
  }) {
    return BaseLocation(
      files ?? fileIDs,
      location ?? this.location,
      isCurrentBase ?? this.isCurrentBase,
      firstCreationTime: firstCreationTime ?? this.firstCreationTime,
      lastCreationTime: lastCreationTime ?? this.lastCreationTime,
    );
  }
}
