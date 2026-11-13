import "package:flutter_map/flutter_map.dart";
import 'package:photos/models/file/file.dart';

class ImageMarker {
  final EnteFile imageFile;
  final double latitude;
  final double longitude;
  final int imageCount;
  final LatLngBounds? clusterBounds;

  ImageMarker({
    required this.imageFile,
    required this.latitude,
    required this.longitude,
    this.imageCount = 1,
    this.clusterBounds,
  });
}
