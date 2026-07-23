import "dart:convert";
import "dart:io";
import "dart:math";

import "package:computer/computer.dart";
import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:flutter/foundation.dart";
import "package:logging/logging.dart";
import "package:photos/core/constants.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/events/location_tag_updated_event.dart";
import "package:photos/gateways/entity/models/type.dart";
import "package:photos/models/base_location.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/local_entity_data.dart";
import "package:photos/models/location/location.dart";
import 'package:photos/models/location_tag/location_tag.dart';
import "package:photos/service_locator.dart";
import "package:photos/services/remote_assets_service.dart";
import "package:shared_preferences/shared_preferences.dart";

const double earthRadius = 6371; // Earth's radius in kilometers

class LocationService {
  final SharedPreferences prefs;
  final Logger _logger = Logger((LocationService).toString());
  final Computer _computer = Computer.shared();

  // If the discovery section is loaded before the cities are loaded, then we
  // need to refresh the discovery section after the cities are loaded.
  bool reloadLocationDiscoverySection = false;

  static const _kCitiesKdTreeRemotePath =
      "https://assets.ente.com/world_cities.kdtree.bin";

  List<City> _cities = [];
  List<List<int>> _kdTreeNodes = [];
  int _kdTreeRoot = -1;
  double _kdTreeMaxLatDelta = 0;
  double _kdTreeMaxLngDelta = 0;

  // TODO: lau: consider actually using this in location section
  List<BaseLocation> baseLocations = [];

  LocationService(this.prefs) {
    debugPrint('LocationService constructor');
    Future.delayed(const Duration(seconds: 3), () {
      _loadCities();
    });
  }

  Future<Iterable<LocalEntity<LocationTag>>> _getStoredLocationTags() async {
    final data = await entityService.getEntities(EntityType.location);
    return data.map(
      (e) => LocalEntity(LocationTag.fromJson(json.decode(e.data)), e.id),
    );
  }

  Future<Map<LocationTag, int>> getLocationTagsToOccurance(
    List<EnteFile> files,
  ) async {
    final locationTagEntities = await locationService.getLocationTags();

    final locationTagToOccurrence = await _computer.compute(
      _getLocationTagsToOccurenceForIsolate,
      param: {"files": files, "locationTagEntities": locationTagEntities},
    );

    return locationTagToOccurrence;
  }

  Future<Map<City, List<EnteFile>>> getFilesInCity(
    List<EnteFile> allFiles,
    String query,
  ) async {
    // check if the cities where not loaded when discovery section was loaded
    if (allFiles.isNotEmpty && _cities.isEmpty && query.isEmpty) {
      reloadLocationDiscoverySection = true;
    }
    final EnteWatch w = EnteWatch("cities_search")..start();
    w.log('start for files ${allFiles.length} and query $query');
    final args = <String, dynamic>{
      "query": query,
      "cities": _cities,
      "files": allFiles,
    };
    if (_kdTreeNodes.isNotEmpty && _kdTreeRoot >= 0) {
      args["kdTreeNodes"] = _kdTreeNodes;
      args["kdTreeRoot"] = _kdTreeRoot;
      args["kdTreeMaxLatDelta"] = _kdTreeMaxLatDelta;
      args["kdTreeMaxLngDelta"] = _kdTreeMaxLngDelta;
    }
    final result = await _computer.compute(getCityResults, param: args);
    w.log(
      'end for query: $query  on ${allFiles.length} files, found '
      '${result.length} cities',
    );
    return result;
  }

  Future<List<City>> getCities() async {
    if (_cities.isEmpty) {
      await _loadCities();
    }
    return _cities;
  }

  Future<Iterable<LocalEntity<LocationTag>>> getLocationTags() {
    return _getStoredLocationTags();
  }

  Future<void> addLocation(
    String location,
    Location centerPoint,
    double radius,
  ) async {
    //The area enclosed by the location tag will be a circle on a 3D spherical
    //globe and an ellipse on a 2D Mercator projection (2D map)
    //a & b are the semi-major and semi-minor axes of the ellipse
    //Converting the unit from kilometers to degrees for a and b as that is
    //the unit on the caritesian plane

    try {
      final a =
          (radius * scaleFactor(centerPoint.latitude!)) / kilometersPerDegree;
      final b = radius / kilometersPerDegree;
      final locationTag = LocationTag(
        name: location,
        radius: radius,
        aSquare: a * a,
        bSquare: b * b,
        centerPoint: centerPoint,
      );
      await entityService.addOrUpdate(
        EntityType.location,
        locationTag.toJson(),
      );
      Bus.instance.fire(LocationTagUpdatedEvent(LocTagEventType.add));
    } catch (e, s) {
      _logger.severe("Failed to add location tag", e, s);
    }
  }

  Future<List<LocalEntity<LocationTag>>> enclosingLocationTags(
    Location fileCoordinates,
  ) async {
    try {
      final result = List<LocalEntity<LocationTag>>.of([]);
      final locationTagEntities = await getLocationTags();
      for (LocalEntity<LocationTag> locationTagEntity in locationTagEntities) {
        final locationTag = locationTagEntity.item;
        final x = fileCoordinates.latitude! - locationTag.centerPoint.latitude!;
        final y =
            fileCoordinates.longitude! - locationTag.centerPoint.longitude!;
        if ((x * x) / (locationTag.aSquare) + (y * y) / (locationTag.bSquare) <=
            1) {
          result.add(locationTagEntity);
        }
      }
      return result;
    } catch (e, s) {
      _logger.severe("Failed to get enclosing location tags", e, s);
      rethrow;
    }
  }

  /// returns [lat, lng]
  List<String>? convertLocationToDMS(Location centerPoint) {
    if (centerPoint.latitude == null || centerPoint.longitude == null) {
      return null;
    }
    final lat = centerPoint.latitude!;
    final long = centerPoint.longitude!;
    final latRef = lat >= 0 ? "N" : "S";
    final longRef = long >= 0 ? "E" : "W";
    final latDMS = _convertCoordinateToDMS(lat.abs());
    final longDMS = _convertCoordinateToDMS(long.abs());

    return [
      "${latDMS[0]}°${latDMS[1]}'${latDMS[2]}\" $latRef",
      "${longDMS[0]}°${longDMS[1]}'${longDMS[2]}\" $longRef",
    ];
  }

  List<int> _convertCoordinateToDMS(double coordinate) {
    final degrees = coordinate.floor();
    final minutes = ((coordinate - degrees) * 60).floor();
    final seconds = ((coordinate - degrees - minutes / 60) * 3600).floor();
    return [degrees, minutes, seconds];
  }

  ///Will only update if there is a change in the locationTag's properties
  Future<void> updateLocationTag({
    required LocalEntity<LocationTag> locationTagEntity,
    double? newRadius,
    Location? newCenterPoint,
    String? newName,
  }) async {
    try {
      final radius = newRadius ?? locationTagEntity.item.radius;
      final centerPoint = newCenterPoint ?? locationTagEntity.item.centerPoint;
      final name = newName ?? locationTagEntity.item.name;

      final locationTag = locationTagEntity.item;
      //Exit if there is no change in locationTag's properties
      if (radius == locationTag.radius &&
          centerPoint == locationTag.centerPoint &&
          name == locationTag.name) {
        return;
      }
      final a =
          (radius * scaleFactor(centerPoint.latitude!)) / kilometersPerDegree;
      final b = radius / kilometersPerDegree;
      final updatedLoationTag = locationTagEntity.item.copyWith(
        centerPoint: centerPoint,
        aSquare: a * a,
        bSquare: b * b,
        radius: radius,
        name: name,
      );

      await entityService.addOrUpdate(
        EntityType.location,
        updatedLoationTag.toJson(),
        id: locationTagEntity.id,
      );
      Bus.instance.fire(
        LocationTagUpdatedEvent(
          LocTagEventType.update,
          updatedLocTagEntities: [
            LocalEntity(updatedLoationTag, locationTagEntity.id),
          ],
        ),
      );
    } catch (e, s) {
      _logger.severe("Failed to update location tag", e, s);
      rethrow;
    }
  }

  Future<void> deleteLocationTag(String locTagEntityId) async {
    try {
      await entityService.deleteEntry(locTagEntityId);
      Bus.instance.fire(LocationTagUpdatedEvent(LocTagEventType.delete));
    } catch (e, s) {
      _logger.severe("Failed to delete location tag", e, s);
      rethrow;
    }
  }

  void _applyKdTreeLoadResult(Map<String, dynamic> result) {
    _cities = result["cities"] as List<City>;
    _kdTreeNodes = (result["nodes"] as List).cast<List<int>>();
    _kdTreeRoot = result["root"] as int;
    _kdTreeMaxLatDelta = (result["maxLatDelta"] as num).toDouble();
    _kdTreeMaxLngDelta = (result["maxLngDelta"] as num).toDouble();
  }

  Future<void> _loadCities() async {
    final startTime = DateTime.now();
    try {
      final file = await RemoteAssetsService.instance.getAsset(
        _kCitiesKdTreeRemotePath,
      );
      final kdTreeResult = await _computer.compute(
        parseCitiesFromKdTreeBin,
        param: {"filePath": file.path},
      );
      _applyKdTreeLoadResult(kdTreeResult);
      _logger.info(
        "Loaded KD-tree cities from CDN in ${(DateTime.now().millisecondsSinceEpoch - startTime.millisecondsSinceEpoch)}ms, reloadingDiscovery: $reloadLocationDiscoverySection",
      );
      if (reloadLocationDiscoverySection) {
        reloadLocationDiscoverySection = false;
        Bus.instance.fire(
          LocationTagUpdatedEvent(LocTagEventType.dataSetLoaded),
        );
      }
    } catch (e, s) {
      _logger.severe("Failed to load KD-tree cities", e, s);
    }
  }
}

Map<LocationTag, int> _getLocationTagsToOccurenceForIsolate(Map args) {
  final List<EnteFile> files = args["files"];

  final locationTagToOccurence = <LocationTag, int>{};
  final locationTagEntities =
      args["locationTagEntities"] as Iterable<LocalEntity<LocationTag>>;

  for (EnteFile file in files) {
    if (file.uploadedFileID == null ||
        file.uploadedFileID == -1 ||
        !file.hasLocation) {
      continue;
    }
    for (LocalEntity<LocationTag> locationTagEntity in locationTagEntities) {
      final locationTag = locationTagEntity.item;
      final fileCoordinates = file.location!;
      if (isFileInsideLocationTag(
        locationTag.centerPoint,
        fileCoordinates,
        locationTag.radius,
      )) {
        locationTagToOccurence.update(
          locationTag,
          (value) => value + 1,
          ifAbsent: () => 1,
        );
      }
    }
  }

  return locationTagToOccurence;
}

Future<Map<String, dynamic>> parseCitiesFromKdTreeBin(Map args) async {
  final String filePath = args["filePath"] as String;
  final payload = ByteData.sublistView(await File(filePath).readAsBytes());
  final buffer = payload.buffer;
  final baseOffset = payload.offsetInBytes;
  const endian = Endian.little;

  final magic = String.fromCharCodes([
    payload.getUint8(0),
    payload.getUint8(1),
    payload.getUint8(2),
    payload.getUint8(3),
  ]);
  if (magic != "KDT1") {
    throw FormatException("Unsupported KD-tree magic: $magic");
  }
  final headerSize = payload.getUint16(4, endian);
  final version = payload.getUint16(6, endian);
  if (headerSize < 64 || version != 1) {
    throw FormatException(
      "Unsupported KD-tree header: size=$headerSize version=$version",
    );
  }
  final flags = payload.getUint32(8, endian);
  if ((flags & 0x1) == 0) {
    throw const FormatException("Unsupported KD-tree coordinate format");
  }

  final nodeCount = payload.getUint32(12, endian);
  final pointCount = payload.getUint32(16, endian);
  final cityCount = payload.getUint32(20, endian);
  final countryCount = payload.getUint32(24, endian);
  final rootIndex = payload.getInt32(28, endian);
  final nodesOffset = payload.getUint32(32, endian);
  final pointsOffset = payload.getUint32(36, endian);
  final citiesOffsetsOffset = payload.getUint32(40, endian);
  final citiesBlobOffset = payload.getUint32(44, endian);
  final countriesOffsetsOffset = payload.getUint32(48, endian);
  final countriesBlobOffset = payload.getUint32(52, endian);

  final parsedNodes = <List<int>>[];
  final nodesBaseOffset = nodesOffset;
  for (var i = 0; i < nodeCount; i += 1) {
    final nodeOffset = nodesBaseOffset + i * 16;
    parsedNodes.add([
      payload.getInt32(nodeOffset, endian),
      payload.getInt32(nodeOffset + 4, endian),
      payload.getInt32(nodeOffset + 8, endian),
      payload.getInt32(nodeOffset + 12, endian),
    ]);
  }

  final cityOffsets = List<int>.generate(
    cityCount + 1,
    (index) => payload.getUint32(citiesOffsetsOffset + index * 4, endian),
    growable: false,
  );
  final cityBlobLength = cityOffsets[cityCount];
  final cityBlob = Uint8List.view(
    buffer,
    baseOffset + citiesBlobOffset,
    cityBlobLength,
  );
  final cityNames = List<String>.generate(cityCount, (index) {
    final start = cityOffsets[index];
    final end = cityOffsets[index + 1];
    return utf8.decode(cityBlob.sublist(start, end));
  }, growable: false);

  final countryOffsets = List<int>.generate(
    countryCount + 1,
    (index) => payload.getUint32(countriesOffsetsOffset + index * 4, endian),
    growable: false,
  );
  final countryBlobLength = countryOffsets[countryCount];
  final countryBlob = Uint8List.view(
    buffer,
    baseOffset + countriesBlobOffset,
    countryBlobLength,
  );
  final countryNames = List<String>.generate(countryCount, (index) {
    final start = countryOffsets[index];
    final end = countryOffsets[index + 1];
    return utf8.decode(countryBlob.sublist(start, end));
  }, growable: false);

  final cities = <City>[];
  double maxA = 0;
  double maxB = 0;
  final pointsBaseOffset = pointsOffset;
  for (var i = 0; i < pointCount; i += 1) {
    final pointOffset = pointsBaseOffset + i * 16;
    final lat = payload.getFloat32(pointOffset, endian);
    final lng = payload.getFloat32(pointOffset + 4, endian);
    final cityIndex = payload.getUint32(pointOffset + 8, endian);
    final countryIndex = payload.getUint32(pointOffset + 12, endian);
    final a = (defaultCityRadius * scaleFactor(lat)) / kilometersPerDegree;
    const b = defaultCityRadius / kilometersPerDegree;
    cities.add(
      City(
        city: cityNames[cityIndex],
        country: countryNames[countryIndex],
        lat: lat,
        lng: lng,
        a: a,
        aSquare: a * a,
        b: b,
        bSquare: b * b,
      ),
    );
    if (a > maxA) {
      maxA = a;
    }
    if (b > maxB) {
      maxB = b;
    }
  }

  return {
    "cities": cities,
    "nodes": parsedNodes,
    "root": rootIndex,
    "maxLatDelta": maxA,
    "maxLngDelta": maxB,
  };
}

List<int> _kdTreeRangeSearch({
  required List<List<int>> nodes,
  required List<City> cities,
  required int rootIndex,
  required double minLat,
  required double maxLat,
  required double minLng,
  required double maxLng,
}) {
  if (rootIndex < 0 || nodes.isEmpty) {
    return const [];
  }
  final results = <int>[];
  final stack = <int>[rootIndex];
  while (stack.isNotEmpty) {
    final nodeIndex = stack.removeLast();
    if (nodeIndex < 0 || nodeIndex >= nodes.length) {
      continue;
    }
    final node = nodes[nodeIndex];
    final pointIndex = node[0];
    if (pointIndex < 0 || pointIndex >= cities.length) {
      continue;
    }
    final city = cities[pointIndex];
    final lat = city.lat;
    final lng = city.lng;
    if (lat >= minLat && lat <= maxLat && lng >= minLng && lng <= maxLng) {
      results.add(pointIndex);
    }
    final axis = node[3];
    final leftIndex = node[1];
    final rightIndex = node[2];
    if (axis == 0) {
      if (minLat <= lat && leftIndex >= 0 && leftIndex < nodes.length) {
        stack.add(leftIndex);
      }
      if (maxLat >= lat && rightIndex >= 0 && rightIndex < nodes.length) {
        stack.add(rightIndex);
      }
    } else if (axis == 1) {
      if (minLng <= lng && leftIndex >= 0 && leftIndex < nodes.length) {
        stack.add(leftIndex);
      }
      if (maxLng >= lng && rightIndex >= 0 && rightIndex < nodes.length) {
        stack.add(rightIndex);
      }
    } else {
      if (leftIndex >= 0 && leftIndex < nodes.length) {
        stack.add(leftIndex);
      }
      if (rightIndex >= 0 && rightIndex < nodes.length) {
        stack.add(rightIndex);
      }
    }
  }
  return results;
}

Map<City, List<EnteFile>> getCityResults(Map args) {
  final query = (args["query"] as String).toLowerCase();
  final List<City> cities = args["cities"] as List<City>;
  final List<EnteFile> files = args["files"] as List<EnteFile>;
  final kdTreeNodesRaw = args["kdTreeNodes"];
  final List<List<int>> kdTreeNodes = kdTreeNodesRaw is List
      ? kdTreeNodesRaw.cast<List<int>>()
      : const [];
  final int kdTreeRoot = (args["kdTreeRoot"] as int?) ?? -1;
  final double kdTreeMaxLatDelta =
      (args["kdTreeMaxLatDelta"] as num?)?.toDouble() ?? 0;
  final double kdTreeMaxLngDelta =
      (args["kdTreeMaxLngDelta"] as num?)?.toDouble() ?? 0;
  final bool useKdTree =
      kdTreeNodes.isNotEmpty &&
      kdTreeRoot >= 0 &&
      kdTreeMaxLatDelta > 0 &&
      kdTreeMaxLngDelta > 0;

  if (!useKdTree) {
    final matchingCities = cities
        .where((city) => city.city.toLowerCase().contains(query))
        .toList();

    final Map<City, List<EnteFile>> results = {};
    for (final file in files) {
      if (!file.hasLocation) continue; // Skip files without location
      final fileLocation = file.location!;
      for (final city in matchingCities) {
        final x = city.lat - fileLocation.latitude!;
        final y = city.lng - fileLocation.longitude!;

        // Bounding box pre-filter: quick rejection for points clearly outside
        if (x.abs() > city.a || y.abs() > city.b) continue;

        // Ellipse containment check using pre-computed squared parameters
        if ((x * x) / city.aSquare + (y * y) / city.bSquare <= 1) {
          results.putIfAbsent(city, () => []).add(file);
          break; // Stop searching once a file is matched with a city
        }
      }
    }
    return results;
  }

  final bool hasQuery = query.isNotEmpty;
  final Map<City, List<EnteFile>> results = {};
  for (final file in files) {
    if (!file.hasLocation) continue; // Skip files without location
    final fileLocation = file.location!;
    final fileLat = fileLocation.latitude!;
    final fileLng = fileLocation.longitude!;
    final candidateIndices = _kdTreeRangeSearch(
      nodes: kdTreeNodes,
      cities: cities,
      rootIndex: kdTreeRoot,
      minLat: fileLat - kdTreeMaxLatDelta,
      maxLat: fileLat + kdTreeMaxLatDelta,
      minLng: fileLng - kdTreeMaxLngDelta,
      maxLng: fileLng + kdTreeMaxLngDelta,
    );
    int bestIndex = -1;
    for (final cityIndex in candidateIndices) {
      final city = cities[cityIndex];
      if (hasQuery && !city.city.toLowerCase().contains(query)) {
        continue;
      }
      final x = city.lat - fileLat;
      final y = city.lng - fileLng;
      if (x.abs() > city.a || y.abs() > city.b) {
        continue;
      }
      if ((x * x) / city.aSquare + (y * y) / city.bSquare <= 1) {
        if (bestIndex == -1 || cityIndex < bestIndex) {
          bestIndex = cityIndex;
        }
      }
    }
    if (bestIndex != -1) {
      final city = cities[bestIndex];
      results.putIfAbsent(city, () => []).add(file);
    }
  }

  return results;
}

bool isFileInsideLocationTag(
  Location centerPoint,
  Location fileCoordinates,
  double radius,
) {
  final a = (radius * scaleFactor(centerPoint.latitude!)) / kilometersPerDegree;
  final b = radius / kilometersPerDegree;
  final x = centerPoint.latitude! - fileCoordinates.latitude!;
  final y = centerPoint.longitude! - fileCoordinates.longitude!;
  if ((x * x) / (a * a) + (y * y) / (b * b) <= 1) {
    return true;
  }
  return false;
}

double calculateDistance(Location point1, Location point2) {
  final lat1 = point1.latitude! * (pi / 180);
  final lat2 = point2.latitude! * (pi / 180);
  final long1 = point1.longitude! * (pi / 180);
  final long2 = point2.longitude! * (pi / 180);

  // Difference in latitude and longitude
  final dLat = lat2 - lat1;
  final dLong = long2 - long1;

  // Haversine formula
  final a =
      sin(dLat / 2) * sin(dLat / 2) +
      cos(lat1) * cos(lat2) * sin(dLong / 2) * sin(dLong / 2);

  // Angular distance in radians
  final c = 2 * atan2(sqrt(a), sqrt(1 - a));

  return earthRadius * c; // Distance in kilometers
}

///The area bounded by the location tag becomes more elliptical with increase
///in the magnitude of the latitude on the caritesian plane. When latitude is
///0 degrees, the ellipse is a circle with a = b = r. When latitude incrases,
///the major axis (a) has to be scaled by the secant of the latitude.
double scaleFactor(double lat) {
  return 1 / cos(lat * (pi / 180));
}

class City {
  final String city;
  final String country;
  final double lat;
  final double lng;

  /// Pre-computed ellipse parameter for location containment check.
  /// a = (defaultCityRadius * scaleFactor(lat)) / kilometersPerDegree
  final double a;

  /// Pre-computed squared ellipse parameter: a * a
  final double aSquare;

  /// Pre-computed ellipse parameter: defaultCityRadius / kilometersPerDegree
  final double b;

  /// Pre-computed squared ellipse parameter: b * b
  final double bSquare;

  City({
    required this.city,
    required this.country,
    required this.lat,
    required this.lng,
    required this.a,
    required this.aSquare,
    required this.b,
    required this.bSquare,
  });

  factory City.fromMap(Map<String, dynamic> map) {
    final lat = map['lat']?.toDouble() ?? 0.0;
    final a = (defaultCityRadius * scaleFactor(lat)) / kilometersPerDegree;
    const b = defaultCityRadius / kilometersPerDegree;
    return City(
      city: map['city'] ?? '',
      country: map['country'] ?? '',
      lat: lat,
      lng: map['lng']?.toDouble() ?? 0.0,
      a: a,
      aSquare: a * a,
      b: b,
      bSquare: b * b,
    );
  }

  factory City.fromJson(String source) => City.fromMap(json.decode(source));

  @override
  String toString() {
    return 'City(city: $city, country: $country, lat: $lat, lng: $lng)';
  }
}

class GPSData {
  final String? latRef;
  final List<double>? lat;
  final String? longRef;
  final List<double>? long;

  GPSData(this.latRef, this.lat, this.longRef, this.long);

  Location? toLocationObj() {
    int? latSign;
    int? longSign;
    if (lat == null || long == null) {
      return null;
    }
    if (lat!.length < 3 || long!.length < 3) {
      return null;
    }
    if (latRef == null && longRef == null) {
      latSign = lat!.any((element) => element < 0) ? -1 : 1;
      longSign = long!.any((element) => element < 0) ? -1 : 1;

      for (var element in lat!) {
        lat![lat!.indexOf(element)] = element.abs();
      }
      for (var element in long!) {
        long![long!.indexOf(element)] = element.abs();
      }
    } else {
      if (latRef!.toLowerCase().startsWith('n')) {
        latSign = 1;
      } else if (latRef!.toLowerCase().startsWith('s')) {
        latSign = -1;
      }
      if (longRef!.toLowerCase().startsWith('e')) {
        longSign = 1;
      } else if (longRef!.toLowerCase().startsWith('w')) {
        longSign = -1;
      }
    }

    //At this point, latSign and longSign will only be null if latRef and longRef
    //is of invalid format.
    if (latSign == null || longSign == null) {
      return null;
    }

    final result = Location(
      latitude: latSign * (lat![0] + lat![1] / 60 + lat![2] / 3600),
      longitude: longSign * (long![0] + long![1] / 60 + long![2] / 3600),
    );
    if (Location.isValidLocation(result)) {
      return result;
    } else {
      return null;
    }
  }
}
