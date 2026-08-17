import "package:flutter/material.dart";

// GPano metadata describes the image as a crop of a full equirectangular
// canvas: https://developers.google.com/streetview/spherical-metadata
class PanoramaViewData {
  const PanoramaViewData({
    required this.fullWidth,
    required this.fullHeight,
    required this.croppedArea,
  });

  final double fullWidth;
  final double fullHeight;
  final Rect croppedArea;

  // Partial panoramas may not cover longitude 0. Start at the crop's center.
  double get initialLongitude {
    final double uCenter =
        (croppedArea.left + croppedArea.width / 2) / fullWidth;
    double longitude = (uCenter - 0.5) * 360;
    if (longitude > 180) longitude -= 360;
    if (longitude < -180) longitude += 360;
    return longitude;
  }

  double get initialLatitude {
    final double vCenter =
        (croppedArea.top + croppedArea.height / 2) / fullHeight;
    return (0.5 - vCenter) * 180;
  }

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

    // Samsung panoramas can omit the full height.
    if (fHeight == null && fWidth != null && cHeight != null) {
      fHeight = (fWidth / 2).round().toDouble();
      cTop = ((fHeight - cHeight) / 2).round().toDouble();
    }

    // Some rotated images report the cropped and full sizes inconsistently.
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
        inconsistent = true;
        final tmp = ch;
        ch = cw;
        cw = tmp;
      }

      if (cw > fw) {
        inconsistent = true;
        final tmp = fw;
        fw = cw;
        cw = tmp;
      }

      if (ch > fh) {
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

    final values = [cLeft, cTop, cWidth, cHeight, fWidth, fHeight];
    if (values.any((value) => !value.isFinite) ||
        fWidth <= 0 ||
        fHeight <= 0 ||
        cLeft < 0 ||
        cTop < 0 ||
        cWidth <= 0 ||
        cHeight <= 0 ||
        cLeft + cWidth > fWidth ||
        cTop + cHeight > fHeight) {
      return null;
    }

    return PanoramaViewData(
      fullWidth: fWidth,
      fullHeight: fHeight,
      croppedArea: Rect.fromLTWH(cLeft, cTop, cWidth, cHeight),
    );
  }
}
