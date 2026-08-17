import "dart:ui";

class PanoramaView {
  const PanoramaView({this.longitude = 0, this.latitude = 0, this.zoom = 1});

  // Horizontal angle in degrees.
  final double longitude;

  // Vertical angle in degrees.
  final double latitude;

  // Relative to the viewer's base field of view.
  final double zoom;

  PanoramaView copyWith({double? longitude, double? latitude, double? zoom}) {
    return PanoramaView(
      longitude: longitude ?? this.longitude,
      latitude: latitude ?? this.latitude,
      zoom: zoom ?? this.zoom,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is PanoramaView &&
        longitude == other.longitude &&
        latitude == other.latitude &&
        zoom == other.zoom;
  }

  @override
  int get hashCode => Object.hash(longitude, latitude, zoom);
}

class PanoramaGeometry {
  PanoramaGeometry({required this.fullSize, required this.croppedArea}) {
    final values = [
      fullSize.width,
      fullSize.height,
      croppedArea.left,
      croppedArea.top,
      croppedArea.width,
      croppedArea.height,
    ];
    if (values.any((value) => !value.isFinite) ||
        fullSize.width <= 0 ||
        fullSize.height <= 0 ||
        croppedArea.left < 0 ||
        croppedArea.top < 0 ||
        croppedArea.width <= 0 ||
        croppedArea.height <= 0 ||
        croppedArea.right > fullSize.width ||
        croppedArea.bottom > fullSize.height) {
      throw ArgumentError("Crop must be inside a finite, positive full size");
    }
  }

  const PanoramaGeometry.fullSphere()
    : fullSize = const Size(1, 1),
      croppedArea = const Rect.fromLTWH(0, 0, 1, 1);

  // Complete equirectangular canvas dimensions in pixels.
  final Size fullSize;

  // Source image bounds within fullSize, in pixels.
  final Rect croppedArea;
  Rect get normalizedCrop => Rect.fromLTRB(
    croppedArea.left / fullSize.width,
    croppedArea.top / fullSize.height,
    croppedArea.right / fullSize.width,
    croppedArea.bottom / fullSize.height,
  );

  PanoramaView get centeredView {
    final crop = normalizedCrop;
    return PanoramaView(
      longitude: _normalizeLongitude((crop.center.dx - 0.5) * 360),
      latitude: (0.5 - crop.center.dy) * 180,
    );
  }

  bool get coversFullWidth {
    return croppedArea.left == 0 && croppedArea.right == fullSize.width;
  }

  bool get coversFullSphere {
    return coversFullWidth &&
        croppedArea.top == 0 &&
        croppedArea.bottom == fullSize.height;
  }

  @override
  bool operator ==(Object other) {
    return other is PanoramaGeometry &&
        fullSize == other.fullSize &&
        croppedArea == other.croppedArea;
  }

  @override
  int get hashCode => Object.hash(fullSize, croppedArea);
}

double _normalizeLongitude(double value) {
  var result = (value + 180) % 360;
  if (result < 0) result += 360;
  return result - 180;
}
