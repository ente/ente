import "dart:math" as math;
import "dart:ui";

import "package:ente_panorama_viewer/src/models.dart";
import "package:flutter/foundation.dart";

const double _degreesToRadians = math.pi / 180;
const double _radiansToDegrees = 180 / math.pi;
const double _baseHalfFieldOfView = 37.5 * _degreesToRadians;
const double _defaultMaximumZoom = 5;

class PanoramaCamera extends ChangeNotifier {
  PanoramaCamera({
    required PanoramaGeometry geometry,
    PanoramaView? initialView,
  }) : _geometry = geometry,
       _view = initialView ?? geometry.centeredView;

  PanoramaGeometry _geometry;
  PanoramaView _view;
  Size _viewport = Size.zero;
  double _minimumZoom = 1;
  double _cropFitZoom = 1;
  double _maximumZoom = _defaultMaximumZoom;

  PanoramaView get view => _view;
  PanoramaGeometry get geometry => _geometry;
  Size get viewport => _viewport;
  double get minimumZoom => _minimumZoom;
  double get cropFitZoom => _cropFitZoom;
  double get maximumZoom => _maximumZoom;

  double get verticalFieldOfView {
    return 2 *
        math.atan(math.tan(_baseHalfFieldOfView) / _view.zoom) *
        _radiansToDegrees;
  }

  double get horizontalFieldOfView {
    if (_viewport.isEmpty) return verticalFieldOfView;
    final aspect = _viewport.width / _viewport.height;
    return 2 *
        math.atan(math.tan(_baseHalfFieldOfView) / _view.zoom * aspect) *
        _radiansToDegrees;
  }

  bool updateViewport(Size viewport, {bool notify = true}) {
    if (viewport.isEmpty || viewport == _viewport) return false;
    final firstViewport = _viewport.isEmpty;
    final previousCropFitZoom = _cropFitZoom;
    _viewport = viewport;
    _recomputeZoomLimits();
    final shouldFitCrop =
        firstViewport ||
        ((_view.zoom - previousCropFitZoom).abs() < 1e-6 &&
            _cropFitZoom > _view.zoom);
    final candidate = shouldFitCrop
        ? _view.copyWith(zoom: math.max(_view.zoom, _cropFitZoom))
        : _view;
    return _setView(candidate, notify: notify);
  }

  void updateGeometry(PanoramaGeometry geometry, {bool notify = true}) {
    if (geometry == _geometry) return;
    _geometry = geometry;
    _recomputeZoomLimits();
    _setView(_view, notify: notify);
  }

  void reset(PanoramaView? initialView, {bool notify = true}) {
    _recomputeZoomLimits();
    final candidate = initialView ?? _geometry.centeredView;
    _setView(
      candidate.copyWith(zoom: math.max(candidate.zoom, _cropFitZoom)),
      notify: notify,
    );
  }

  bool setView(PanoramaView view) => _setView(view, notify: true);

  bool wouldConstrain(PanoramaView candidate) {
    if (!candidate.longitude.isFinite ||
        !candidate.latitude.isFinite ||
        !candidate.zoom.isFinite) {
      return true;
    }
    final constrained = _clamp(candidate);
    return shortestLongitudeDelta(
              candidate.longitude,
              constrained.longitude,
            ).abs() >
            1e-9 ||
        (candidate.latitude - constrained.latitude).abs() > 1e-9 ||
        (candidate.zoom - constrained.zoom).abs() > 1e-9;
  }

  bool _setView(PanoramaView candidate, {required bool notify}) {
    final clamped = _clamp(candidate);
    if (clamped == _view) return false;
    _view = clamped;
    if (notify) notifyListeners();
    return true;
  }

  PanoramaView _clamp(PanoramaView candidate) {
    final centered = _geometry.centeredView;
    final candidateZoom = candidate.zoom.isFinite
        ? candidate.zoom
        : (_view.zoom.isFinite ? _view.zoom : centered.zoom);
    final candidateLatitude = candidate.latitude.isFinite
        ? candidate.latitude
        : (_view.latitude.isFinite ? _view.latitude : centered.latitude);
    final candidateLongitude = candidate.longitude.isFinite
        ? candidate.longitude
        : (_view.longitude.isFinite ? _view.longitude : centered.longitude);
    final zoom = candidateZoom.clamp(_minimumZoom, _maximumZoom).toDouble();
    final verticalHalf = _verticalHalfFieldOfView(zoom);
    final crop = _geometry.normalizedCrop;
    final cropTop = (0.5 - crop.top) * math.pi;
    final cropBottom = (0.5 - crop.bottom) * math.pi;
    final poleLimit = math.pi / 2 - verticalHalf;
    var minimumLatitude = math.max(cropBottom, -poleLimit);
    var maximumLatitude = math.min(cropTop, poleLimit);
    if (minimumLatitude > maximumLatitude) {
      final center = ((cropTop + cropBottom) / 2)
          .clamp(-poleLimit, poleLimit)
          .toDouble();
      minimumLatitude = center;
      maximumLatitude = center;
    }
    final latitude = (candidateLatitude * _degreesToRadians)
        .clamp(minimumLatitude, maximumLatitude)
        .toDouble();

    double longitude;
    if (_geometry.coversFullWidth || _viewport.isEmpty) {
      longitude = normalizeLongitude(candidateLongitude);
    } else {
      final cropLeft = (crop.left - 0.5) * 2 * math.pi;
      final cropRight = (crop.right - 0.5) * 2 * math.pi;
      longitude = (candidateLongitude * _degreesToRadians)
          .clamp(cropLeft, cropRight)
          .toDouble();
      longitude *= _radiansToDegrees;
    }

    return PanoramaView(
      longitude: longitude,
      latitude: latitude * _radiansToDegrees,
      zoom: zoom,
    );
  }

  void _recomputeZoomLimits() {
    if (_viewport.isEmpty) {
      _minimumZoom = 1;
      _cropFitZoom = 1;
      _maximumZoom = _defaultMaximumZoom;
      return;
    }

    final crop = _geometry.normalizedCrop;
    final halfVerticalCrop = crop.height * math.pi / 2;
    final verticalZoom = halfVerticalCrop >= _baseHalfFieldOfView
        ? 1.0
        : math.tan(_baseHalfFieldOfView) / math.tan(halfVerticalCrop);

    var horizontalZoom = 1.0;
    if (!_geometry.coversFullWidth) {
      final targetWidth = crop.width * 2 * math.pi;
      final centerLatitude = (0.5 - crop.center.dy) * math.pi;
      bool fits(double zoom) {
        final extent = _relativeLongitudeExtent(
          latitude: centerLatitude,
          zoom: zoom,
        );
        return extent.maximum - extent.minimum <= targetWidth;
      }

      var upper = 1.0;
      while (!fits(upper)) {
        upper *= 2;
      }
      var lower = 1.0;
      for (var index = 0; index < 40; index++) {
        final middle = (lower + upper) / 2;
        if (fits(middle)) {
          upper = middle;
        } else {
          lower = middle;
        }
      }
      horizontalZoom = upper;
    }

    _minimumZoom = 1;
    _cropFitZoom = math.max(1, math.max(verticalZoom, horizontalZoom));
    _maximumZoom = math.max(_defaultMaximumZoom, _cropFitZoom);
  }

  _AngularExtent _relativeLongitudeExtent({
    required double latitude,
    required double zoom,
  }) {
    if (_viewport.isEmpty) return const _AngularExtent(0, 0);
    var minimum = double.infinity;
    var maximum = double.negativeInfinity;
    for (final y in const [-1.0, 1.0]) {
      for (final x in const [-1.0, 1.0]) {
        final angles = _rayAngles(
          normalizedX: x,
          normalizedY: y,
          longitude: 0,
          latitude: latitude,
          zoom: zoom,
        );
        minimum = math.min(minimum, angles.longitude);
        maximum = math.max(maximum, angles.longitude);
      }
    }
    return _AngularExtent(minimum, maximum);
  }

  Offset sourcePointAt(Offset localPosition) {
    return _sourcePointAt(_view, localPosition);
  }

  Offset _sourcePointAt(PanoramaView view, Offset localPosition) {
    if (_viewport.isEmpty) return Offset.zero;
    final x = localPosition.dx / _viewport.width * 2 - 1;
    final y = 1 - localPosition.dy / _viewport.height * 2;
    final angles = _rayAngles(
      normalizedX: x,
      normalizedY: y,
      longitude: view.longitude * _degreesToRadians,
      latitude: view.latitude * _degreesToRadians,
      zoom: view.zoom,
    );
    var u = 0.5 + angles.longitude / (2 * math.pi);
    if (_geometry.coversFullWidth) {
      u %= 1;
      if (u < 0) u += 1;
    } else {
      final crop = _geometry.normalizedCrop;
      if (crop.right > 0.99999 && u < crop.left) {
        u += 1;
      } else if (crop.left < 0.00001 && u > crop.right) {
        u -= 1;
      }
    }
    final v = 0.5 - angles.latitude / math.pi;
    return Offset(u, v);
  }

  bool anchorSourcePoint(Offset localPosition, Offset sourcePoint) {
    var candidate = _view;
    for (var iteration = 0; iteration < 3; iteration++) {
      final current = _sourcePointAt(candidate, localPosition);
      final longitudeDelta = shortestLongitudeDelta(
        current.dx * 360,
        sourcePoint.dx * 360,
      );
      final latitudeDelta = (current.dy - sourcePoint.dy) * 180;
      candidate = candidate.copyWith(
        longitude: candidate.longitude + longitudeDelta,
        latitude: candidate.latitude + latitudeDelta,
      );
      candidate = _clamp(candidate);
    }
    return _setView(candidate, notify: true);
  }

  _RayAngles _rayAngles({
    required double normalizedX,
    required double normalizedY,
    required double longitude,
    required double latitude,
    required double zoom,
  }) {
    final aspect = _viewport.width / _viewport.height;
    final projection = math.tan(_baseHalfFieldOfView) / zoom;
    var x = normalizedX * aspect * projection;
    var y = normalizedY * projection;
    var z = 1.0;
    final inverseLength = 1 / math.sqrt(x * x + y * y + z * z);
    x *= inverseLength;
    y *= inverseLength;
    z *= inverseLength;

    final sinLatitude = math.sin(latitude);
    final cosLatitude = math.cos(latitude);
    final pitchedY = cosLatitude * y + sinLatitude * z;
    final pitchedZ = -sinLatitude * y + cosLatitude * z;

    final sinLongitude = math.sin(longitude);
    final cosLongitude = math.cos(longitude);
    final rotatedX = cosLongitude * x + sinLongitude * pitchedZ;
    final rotatedZ = -sinLongitude * x + cosLongitude * pitchedZ;

    return _RayAngles(
      math.atan2(rotatedX, rotatedZ),
      math.asin(pitchedY.clamp(-1, 1)),
    );
  }

  double _verticalHalfFieldOfView(double zoom) {
    return math.atan(math.tan(_baseHalfFieldOfView) / zoom);
  }

  static double normalizeLongitude(double value) {
    var result = (value + 180) % 360;
    if (result < 0) result += 360;
    return result - 180;
  }

  static double shortestLongitudeDelta(double from, double to) {
    return normalizeLongitude(to - from);
  }
}

class _AngularExtent {
  const _AngularExtent(this.minimum, this.maximum);

  final double minimum;
  final double maximum;
}

class _RayAngles {
  const _RayAngles(this.longitude, this.latitude);

  final double longitude;
  final double latitude;
}
