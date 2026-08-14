import 'dart:io';
import 'dart:ui';

enum ScanColorMode { auto, color, grayscale }

/// Four corners in the detector's 256x256 mask space, clockwise from
/// top-left. Mask space maps proportionally onto the upright frame it
/// describes (live preview frame or source capture).
class ScanQuad {
  const ScanQuad(this.corners);

  static const double maskSide = 256;

  final List<Offset> corners;

  factory ScanQuad.fullFrame() => const ScanQuad([
    Offset(0, 0),
    Offset(maskSide, 0),
    Offset(maskSide, maskSide),
    Offset(0, maskSide),
  ]);
}

class ScannedPage {
  const ScannedPage({
    required this.id,
    required this.sourceJpeg,
    required this.processedJpeg,
    required this.quad,
    required this.rotationDegrees,
    required this.resolvedColorMode,
    required this.width,
    required this.height,
  });

  final String id;

  /// The upright (EXIF-normalized) capture, kept for re-cropping.
  final File sourceJpeg;

  /// Rendered output; crop, enhancement and [rotationDegrees] are baked in.
  final File processedJpeg;

  /// Quad used for the render, in mask space of [sourceJpeg].
  final ScanQuad quad;

  final int rotationDegrees;

  /// Color or grayscale after auto-detection resolved.
  final ScanColorMode resolvedColorMode;

  /// Dimensions of [processedJpeg].
  final int width;
  final int height;

  ScannedPage copyWith({
    File? processedJpeg,
    ScanQuad? quad,
    int? rotationDegrees,
    ScanColorMode? resolvedColorMode,
    int? width,
    int? height,
  }) => ScannedPage(
    id: id,
    sourceJpeg: sourceJpeg,
    processedJpeg: processedJpeg ?? this.processedJpeg,
    quad: quad ?? this.quad,
    rotationDegrees: rotationDegrees ?? this.rotationDegrees,
    resolvedColorMode: resolvedColorMode ?? this.resolvedColorMode,
    width: width ?? this.width,
    height: height ?? this.height,
  );
}
