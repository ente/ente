import "dart:math" as math;
import "dart:ui";

import "package:ente_components/ente_components.dart";

class PdfPageLayout {
  PdfPageLayout({
    required this.pageSizes,
    required this.viewportWidth,
    required this.viewportHeight,
    required this.topInset,
    required this.bottomPadding,
  }) : contentWidth = viewportWidth - horizontalPadding * 2,
       offsets = List.filled(pageSizes.length + 1, topInset) {
    for (var i = 0; i < pageSizes.length; i++) {
      offsets[i + 1] = offsets[i] + contentWidth / _aspect(pageSizes[i]) + gap;
    }
  }

  static const horizontalPadding = Spacing.lg;
  static const gap = Spacing.md;
  static const _fallbackAspect = 1 / 1.414;

  final List<Size> pageSizes;
  final double viewportWidth;
  final double viewportHeight;
  final double topInset;
  final double bottomPadding;
  final double contentWidth;
  final List<double> offsets;

  int get pageCount => pageSizes.length;

  double get contentHeight =>
      math.max(viewportHeight, offsets.last - gap + bottomPadding);

  static double _aspect(Size size) {
    final aspect = size.width / size.height;
    return aspect.isFinite && aspect > 0 ? aspect : _fallbackAspect;
  }

  double pageTop(int index) => offsets[index];

  double pageHeight(int index) => offsets[index + 1] - offsets[index] - gap;

  int pageAt(double y) {
    final index = offsets.lastIndexWhere((offset) => offset <= y);
    return index.clamp(0, pageCount - 1);
  }

  int currentPage(double top, double bottom) {
    var best = pageAt(top);
    var bestFraction = -1.0;
    for (var index = best; index <= pageAt(bottom); index++) {
      final height = pageHeight(index);
      final pageBottom = pageTop(index) + height;
      final visible =
          math.min(bottom, pageBottom) - math.max(top, pageTop(index));
      if (visible / height > bestFraction) {
        best = index;
        bestFraction = visible / height;
      }
    }
    return best;
  }

  (int, int) visibleRange(double top, double bottom, {int margin = 1}) {
    final first = math.max(0, pageAt(top) - margin);
    final last = math.min(pageCount - 1, pageAt(bottom) + margin);
    return (first, last);
  }

  double clampTranslationY(double y, double scale) =>
      y.clamp(viewportHeight - contentHeight * scale, 0.0);

  int renderWidth(
    int index, {
    required double pixelRatio,
    required int scale,
    required int maxPixels,
  }) {
    final wanted = contentWidth * pixelRatio * scale;
    final capped = math.sqrt(maxPixels * _aspect(pageSizes[index]));
    return math.max(1, math.min(wanted, capped).round());
  }

  int renderHeight(int index, int width) =>
      math.max(1, (width / _aspect(pageSizes[index])).round());

  static int zoomBucket(double scale, {required double maxScale}) =>
      scale.clamp(1.0, maxScale).ceil();
}
