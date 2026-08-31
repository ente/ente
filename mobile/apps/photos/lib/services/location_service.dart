import "dart:convert";
import "dart:math";

import "package:computer/computer.dart";
import "package:connectivity_plus/connectivity_plus.dart";
import "package:ente_photos_platform/ente_photos_platform.dart";
import "package:logging/logging.dart";
import "package:path_provider/path_provider.dart";
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
import "package:photos/services/native_country_locales.dart";
import "package:photos/src/rust/api/location_api.dart" as rust;

const double earthRadius = 6371; // Earth's radius in kilometers

class CitySearchIndex {
  final Map<EnteFile, City> assignments;

  const CitySearchIndex(this.assignments);

  Map<City, List<EnteFile>> match(List<EnteFile> files) {
    final results = <City, List<EnteFile>>{};
    for (final file in files) {
      final city = assignments[file];
      if (city != null) results.putIfAbsent(city, () => []).add(file);
    }
    return results;
  }
}

class LocationService {
  final Logger _logger = Logger((LocationService).toString());
  final Computer _computer = Computer.shared();

  // Refresh discovery if it ran before the city index loaded.
  bool reloadLocationDiscoverySection = false;

  rust.LocationIndex? _index;
  Future<rust.LocationIndex?>? _loading;
  bool _indexLoadFailed = false;
  bool _retryIndexAfterLoad = false;
  final _countryNames = <String, CountryNames>{};

  // TODO: lau: consider actually using this in location section
  List<BaseLocation> baseLocations = [];

  LocationService() {
    Connectivity().onConnectivityChanged.listen((connections) {
      if (!connections.any((result) => result != ConnectivityResult.none)) {
        return;
      }
      if (_loading != null) {
        _retryIndexAfterLoad = true;
      } else if (_indexLoadFailed) {
        _indexLoadFailed = false;
        _loadIndex();
      }
    });
    Future.delayed(const Duration(seconds: 3), () {
      _loadIndex();
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
    final index = await _loadIndex();
    if (index == null) {
      if (allFiles.isNotEmpty && query.isEmpty) {
        reloadLocationDiscoverySection = true;
      }
      return {};
    }
    final files = allFiles.where((file) => file.hasLocation).toList();
    final groups = await index.groupCities(
      coordinates: _coordinates(files),
      query: query,
    );
    return {
      for (final group in groups)
        _city(group.city): [
          for (final position in group.coordinateIndices) files[position],
        ],
    };
  }

  Future<Map<String, List<EnteFile>>> getFilesInCountry(
    List<EnteFile> allFiles,
    String query,
    String locale,
  ) async {
    if (query.isEmpty) return {};
    final index = await _loadIndex();
    if (index == null) return {};
    final names = _countryNames[locale] ??= await CountryNamesClient.get(
      locale,
      nativeLocales: nativeCountryLocales,
    );
    final matchingCodes = names.matchingCodes(query);
    if (matchingCodes.isEmpty) return {};
    final files = allFiles.where((file) => file.hasLocation).toList();
    final groups = await index.groupCountries(
      coordinates: _coordinates(files),
      region: names.region,
    );
    return {
      for (final group in groups)
        if (matchingCodes.contains(group.code))
          names.names[group.code]!: [
            for (final position in group.coordinateIndices) files[position],
          ],
    };
  }

  Future<List<City>> getCities() async {
    final index = await _loadIndex();
    if (index == null) return [];
    return (await index.cities()).map(_city).toList();
  }

  Future<CitySearchIndex> getCitySearchIndex(
    Iterable<EnteFile> allFiles,
  ) async {
    final files = allFiles.toList();
    final groups = await getFilesInCity(files, '');
    return CitySearchIndex({
      for (final group in groups.entries)
        for (final file in group.value) file: group.key,
    });
  }

  List<rust.LocationCoordinate> _coordinates(List<EnteFile> files) => [
    for (final file in files)
      rust.LocationCoordinate(
        latitude: file.location!.latitude!,
        longitude: file.location!.longitude!,
      ),
  ];

  City _city(rust.LocationCity city) => City(
    city: city.name,
    country: city.country,
    lat: city.latitude,
    lng: city.longitude,
  );

  Future<rust.LocationIndex?> _loadIndex() {
    if (_index != null) return Future.value(_index);
    if (_indexLoadFailed) return Future.value(null);
    return _loading ??= _openIndex();
  }

  Future<rust.LocationIndex?> _openIndex() async {
    final startTime = DateTime.now();
    try {
      final root = (await getApplicationSupportDirectory()).path;
      _index = await rust.openLocationIndex(assetRoot: root);
      _logger.info(
        "Loaded location index in ${DateTime.now().difference(startTime).inMilliseconds}ms, reloadingDiscovery: $reloadLocationDiscoverySection",
      );
      if (reloadLocationDiscoverySection) {
        reloadLocationDiscoverySection = false;
        Bus.instance.fire(
          LocationTagUpdatedEvent(LocTagEventType.dataSetLoaded),
        );
      }
      return _index;
    } catch (e) {
      _logger.warning("Failed to load location index: $e");
      return null;
    } finally {
      final retryAfterLoad = _retryIndexAfterLoad;
      _retryIndexAfterLoad = false;
      _loading = null;
      if (_index == null) {
        if (retryAfterLoad) {
          _loadIndex().ignore();
        } else {
          _indexLoadFailed = true;
        }
      }
    }
  }

  Future<Iterable<LocalEntity<LocationTag>>> getLocationTags() {
    return _getStoredLocationTags();
  }

  Future<void> addLocation(
    String location,
    Location centerPoint,
    double radius,
  ) async {
    // A circular radius on the globe maps to an ellipse in Mercator
    // coordinates. Store its axes in degrees for latitude/longitude checks.

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

// Returns kilometers.
double calculateDistance(Location point1, Location point2) {
  final lat1 = point1.latitude! * (pi / 180);
  final lat2 = point2.latitude! * (pi / 180);
  final long1 = point1.longitude! * (pi / 180);
  final long2 = point2.longitude! * (pi / 180);

  final dLat = lat2 - lat1;
  final dLong = long2 - long1;

  final a =
      sin(dLat / 2) * sin(dLat / 2) +
      cos(lat1) * cos(lat2) * sin(dLong / 2) * sin(dLong / 2);

  final c = 2 * atan2(sqrt(a), sqrt(1 - a));

  return earthRadius * c;
}

// Mercator stretches longitude by sec(latitude), so a circle's horizontal
// radius must scale with latitude.
double scaleFactor(double lat) {
  return 1 / cos(lat * (pi / 180));
}

class City {
  final String city;
  final String country;
  final double lat;
  final double lng;

  const City({
    required this.city,
    required this.country,
    required this.lat,
    required this.lng,
  });
}

class GPSData {
  final String? latRef;
  final List<double>? lat;
  final String? longRef;
  final List<double>? long;

  GPSData(this.latRef, this.lat, this.longRef, this.long);

  Location? toLocationObj() {
    final lat = this.lat;
    final long = this.long;
    if (lat == null || long == null || lat.length < 3 || long.length < 3) {
      return null;
    }

    final latRef = this.latRef?.toLowerCase();
    final longRef = this.longRef?.toLowerCase();
    int? latSign;
    int? longSign;
    if (latRef == null && longRef == null) {
      latSign = lat.any((element) => element < 0) ? -1 : 1;
      longSign = long.any((element) => element < 0) ? -1 : 1;
    } else if (latRef == null || longRef == null) {
      return null;
    } else {
      if (latRef.startsWith('n')) {
        latSign = 1;
      } else if (latRef.startsWith('s')) {
        latSign = -1;
      }
      if (longRef.startsWith('e')) {
        longSign = 1;
      } else if (longRef.startsWith('w')) {
        longSign = -1;
      }
    }

    if (latSign == null || longSign == null) {
      return null;
    }

    final latParts = latRef == null
        ? lat.map((part) => part.abs()).toList()
        : lat;
    final longParts = longRef == null
        ? long.map((part) => part.abs()).toList()
        : long;
    final result = Location(
      latitude: latSign * (latParts[0] + latParts[1] / 60 + latParts[2] / 3600),
      longitude:
          longSign * (longParts[0] + longParts[1] / 60 + longParts[2] / 3600),
    );
    if (Location.isValidLocation(result)) {
      return result;
    } else {
      return null;
    }
  }
}
