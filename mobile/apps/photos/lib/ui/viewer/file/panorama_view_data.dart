import "package:flutter/material.dart";

/// View parameters for rendering a (possibly partial) panorama on a sphere,
/// derived from GPano XMP metadata.
///
/// See https://developers.google.com/streetview/spherical-metadata
class PanoramaViewData {
  const PanoramaViewData({
    required this.fullWidth,
    required this.fullHeight,
    required this.croppedArea,
  });

  /// Width in pixels of the full equirectangular canvas.
  final double fullWidth;

  /// Height in pixels of the full equirectangular canvas.
  final double fullHeight;

  /// Area of the full canvas that the image actually covers, in pixels.
  final Rect croppedArea;

  /// Initial camera longitude, in degrees within [-180, 180], that points the
  /// view at the horizontal center of the cropped area.
  ///
  /// The panorama widget maps the cropped area to its absolute position on the
  /// full equirectangular canvas, and its longitude 0 faces the horizontal
  /// center (u = 0.5) of that canvas. Partial panoramas (e.g. Pixel sweep
  /// panoramas) keep the compass heading of the shot, so their cropped area
  /// can sit anywhere on the canvas; without this correction the initial view
  /// often faces an empty part of the sphere.
  double get initialLongitude {
    final double uCenter =
        (croppedArea.left + croppedArea.width / 2) / fullWidth;
    double longitude = (uCenter - 0.5) * 360;
    if (longitude > 180) longitude -= 360;
    if (longitude < -180) longitude += 360;
    return longitude;
  }

  /// Parses GPano attributes extracted from XMP. Returns null when the
  /// metadata is insufficient to place the image on the panorama sphere.
  static PanoramaViewData? fromXmp(Map<String, String> data) {
    double? cWidth = double.tryParse(
      data["GPano:CroppedAreaImageWidthPixels"] ?? "",
    );
    double? cHeight = double.tryParse(
      data["GPano:CroppedAreaImageHeightPixels"] ?? "",
    );
    double? fWidth = double.tryParse(data["GPano:FullPanoWidthPixels"] ?? "");
    double? fHeight = double.tryParse(data["GPano:FullPanoHeightPixels"] ?? "");
    double? cLeft = double.tryParse(data["GPano:CroppedAreaLeftPixels"] ?? "");
    double? cTop = double.tryParse(data["GPano:CroppedAreaTopPixels"] ?? "");

    // handle missing `fullPanoHeight` (e.g. Samsung camera app panorama mode)
    if (fHeight == null && fWidth != null && cHeight != null) {
      fHeight = (fWidth / 2).round().toDouble();
      cTop = ((fHeight - cHeight) / 2).round().toDouble();
    }

    // handle inconsistent sizing (e.g. rotated image taken with OnePlus EB2103)
    if (cWidth != null &&
        cHeight != null &&
        fWidth != null &&
        fHeight != null) {
      double cw = cWidth;
      double ch = cHeight;
      double fw = fWidth;
      double fh = fHeight;
      final croppedOrientation = cw > ch
          ? Orientation.landscape
          : Orientation.portrait;
      final fullOrientation = fw > fh
          ? Orientation.landscape
          : Orientation.portrait;
      var inconsistent = false;
      if (croppedOrientation != fullOrientation) {
        // inconsistent orientation
        inconsistent = true;
        final tmp = ch;
        ch = cw;
        cw = tmp;
      }

      if (cw > fw) {
        // inconsistent full/cropped width
        inconsistent = true;
        final tmp = fw;
        fw = cw;
        cw = tmp;
      }

      if (ch > fh) {
        // inconsistent full/cropped height
        inconsistent = true;
        final tmp = ch;
        ch = fh;
        fh = tmp;
      }

      if (inconsistent) {
        cLeft = ((fw - cw) ~/ 2).toDouble();
        cTop = ((fh - ch) ~/ 2).toDouble();
      }
      cWidth = cw;
      cHeight = ch;
      fWidth = fw;
      fHeight = fh;
    }

    if (cLeft == null ||
        cTop == null ||
        cWidth == null ||
        cHeight == null ||
        fWidth == null ||
        fHeight == null) {
      return null;
    }

    return PanoramaViewData(
      fullWidth: fWidth,
      fullHeight: fHeight,
      croppedArea: Rect.fromLTWH(cLeft, cTop, cWidth, cHeight),
    );
  }
}
