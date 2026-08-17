import "dart:isolate";
import "dart:math";

import "package:flutter_map/flutter_map.dart";

class MapPoint {
  final int imageIndex;
  final double latitude;
  final double longitude;

  const MapPoint({
    required this.imageIndex,
    required this.latitude,
    required this.longitude,
  });
}

class MapMarkerGroup {
  final int imageIndex;
  final double latitude;
  final double longitude;
  final int imageCount;
  final double north;
  final double south;
  final double east;
  final double west;

  const MapMarkerGroup({
    required this.imageIndex,
    required this.latitude,
    required this.longitude,
    required this.imageCount,
    required this.north,
    required this.south,
    required this.east,
    required this.west,
  });

  LatLngBounds get bounds =>
      LatLngBounds.unsafe(north: north, south: south, east: east, west: west);
}

class _ProjectedMarkerGroup {
  final int imageIndex;
  final double latitude;
  final double longitude;
  final double x;
  final double y;
  int imageCount = 1;
  double north;
  double south;
  double east;
  double west;

  _ProjectedMarkerGroup({
    required this.imageIndex,
    required this.latitude,
    required this.longitude,
    required this.x,
    required this.y,
  }) : north = latitude,
       south = latitude,
       east = longitude,
       west = longitude;

  MapMarkerGroup toMarkerGroup() => MapMarkerGroup(
    imageIndex: imageIndex,
    latitude: latitude,
    longitude: longitude,
    imageCount: imageCount,
    north: north,
    south: south,
    east: east,
    west: west,
  );

  void add(MapPoint point) {
    imageCount++;
    north = max(north, point.latitude);
    south = min(south, point.latitude);
    east = max(east, point.longitude);
    west = min(west, point.longitude);
  }
}

class _ProjectedMapPoint {
  final MapPoint point;
  final double x;
  final double y;

  const _ProjectedMapPoint({
    required this.point,
    required this.x,
    required this.y,
  });
}

class MapWorkerInit {
  final List<MapPoint> points;
  final SendPort sendPort;

  const MapWorkerInit({required this.points, required this.sendPort});
}

class MapViewportRequest {
  final int id;
  final LatLngBounds bounds;
  final double zoom;
  final double markerMinX;
  final double markerMinY;
  final double markerMaxX;
  final double markerMaxY;

  const MapViewportRequest({
    required this.id,
    required this.bounds,
    required this.zoom,
    required this.markerMinX,
    required this.markerMinY,
    required this.markerMaxX,
    required this.markerMaxY,
  });
}

class MapViewportResult {
  final int id;
  final List<int> visibleImageIndexes;
  final List<MapMarkerGroup> markerGroups;

  const MapViewportResult({
    required this.id,
    required this.visibleImageIndexes,
    required this.markerGroups,
  });
}

const double _minimumMarkerDistancePixels = 100;
const double _webMercatorTileSize = 256;
const double _mercatorLatitudeLimit = 85.05112878;

void mapWorker(MapWorkerInit init) {
  final receivePort = ReceivePort();
  init.sendPort.send(receivePort.sendPort);
  receivePort.listen((message) {
    if (message is! MapViewportRequest) {
      return;
    }

    final visibleIndexes = <int>[];
    final visiblePoints = <_ProjectedMapPoint>[];
    final bufferedPoints = <_ProjectedMapPoint>[];
    final groupsByCell = <(int, int), List<_ProjectedMarkerGroup>>{};
    final groups = <_ProjectedMarkerGroup>[];
    final scale = _webMercatorTileSize * pow(2, message.zoom).toDouble();

    for (final point in init.points) {
      final isVisible =
          point.longitude >= message.bounds.west &&
          point.longitude <= message.bounds.east &&
          point.latitude >= message.bounds.south &&
          point.latitude <= message.bounds.north;
      if (isVisible) {
        visibleIndexes.add(point.imageIndex);
      }

      final latitude = point.latitude.clamp(
        -_mercatorLatitudeLimit,
        _mercatorLatitudeLimit,
      );
      final sinLatitude = sin(latitude * pi / 180);
      final x = (point.longitude + 180) / 360 * scale;
      final y =
          (0.5 - log((1 + sinLatitude) / (1 - sinLatitude)) / (4 * pi)) * scale;
      if (x < message.markerMinX ||
          x > message.markerMaxX ||
          y < message.markerMinY ||
          y > message.markerMaxY) {
        continue;
      }

      final projectedPoint = _ProjectedMapPoint(point: point, x: x, y: y);
      (isVisible ? visiblePoints : bufferedPoints).add(projectedPoint);
    }

    void addToMarkerGroup(_ProjectedMapPoint projectedPoint) {
      final point = projectedPoint.point;
      final x = projectedPoint.x;
      final y = projectedPoint.y;
      final cell = (
        (x / _minimumMarkerDistancePixels).floor(),
        (y / _minimumMarkerDistancePixels).floor(),
      );
      _ProjectedMarkerGroup? closestGroup;
      var closestDistanceSquared = double.infinity;

      for (var xOffset = -1; xOffset <= 1; xOffset++) {
        for (var yOffset = -1; yOffset <= 1; yOffset++) {
          final nearbyGroups =
              groupsByCell[(cell.$1 + xOffset, cell.$2 + yOffset)];
          if (nearbyGroups == null) {
            continue;
          }

          for (final group in nearbyGroups) {
            final xDistance = x - group.x;
            final yDistance = y - group.y;
            final distanceSquared =
                xDistance * xDistance + yDistance * yDistance;
            if (distanceSquared <=
                    _minimumMarkerDistancePixels *
                        _minimumMarkerDistancePixels &&
                distanceSquared < closestDistanceSquared) {
              closestGroup = group;
              closestDistanceSquared = distanceSquared;
            }
          }
        }
      }

      if (closestGroup != null) {
        closestGroup.add(point);
        return;
      }

      final group = _ProjectedMarkerGroup(
        imageIndex: point.imageIndex,
        latitude: point.latitude,
        longitude: point.longitude,
        x: x,
        y: y,
      );
      groups.add(group);
      groupsByCell.putIfAbsent(cell, () => []).add(group);
    }

    for (final point in visiblePoints) {
      addToMarkerGroup(point);
    }
    for (final point in bufferedPoints) {
      addToMarkerGroup(point);
    }

    init.sendPort.send(
      MapViewportResult(
        id: message.id,
        visibleImageIndexes: visibleIndexes,
        markerGroups: groups
            .map((group) => group.toMarkerGroup())
            .toList(growable: false),
      ),
    );
  });
}
