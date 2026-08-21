import 'dart:io';
import 'dart:ui';

enum ScanColorMode { color, grayscale }

class ScanQuad {
  const ScanQuad(this.corners);

  final List<Offset> corners;

  factory ScanQuad.fullFrame() =>
      const ScanQuad([Offset(0, 0), Offset(1, 0), Offset(1, 1), Offset(0, 1)]);
}

class ScannedPage {
  const ScannedPage({
    required this.id,
    required this.sourceJpeg,
    required this.processedJpeg,
    required this.quad,
    required this.rotationDegrees,
    required this.resolvedColorMode,
    required this.sourceWidth,
    required this.sourceHeight,
    required this.width,
    required this.height,
  });

  final String id;

  final File sourceJpeg;

  final File processedJpeg;

  final ScanQuad quad;

  final int rotationDegrees;

  final ScanColorMode resolvedColorMode;

  final int sourceWidth;
  final int sourceHeight;

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
    sourceWidth: sourceWidth,
    sourceHeight: sourceHeight,
    width: width ?? this.width,
    height: height ?? this.height,
  );
}
