import "dart:math" as math;

import "package:flutter/widgets.dart";

// Flutter's `RSuperellipse` clamps radii so they don't overlap, which means
// radii > (side / 2) become circles. Historically we used an oversized radius
// with `ContinuousRectangleBorder` to approximate the iOS squircle.
//
// This factor produces a similarly "squircled" look without collapsing into a
// circle for the common square thumbnail sizes used across the app.
const double _kFaceThumbnailSquircleRadiusFactor = 0.30;
const double _kFaceThumbnailSquircleMinStraightEdge = 8.0;

BorderRadius faceThumbnailSquircleBorderRadius(double side) {
  final normalizedSide = side.isFinite ? side : 0.0;
  final clampedSide = normalizedSide > 0 ? normalizedSide : 0.0;
  final maxRadius = math.max(
    0.0,
    (clampedSide - _kFaceThumbnailSquircleMinStraightEdge) / 2,
  );
  return BorderRadius.circular(
    math.min(clampedSide * _kFaceThumbnailSquircleRadiusFactor, maxRadius),
  );
}

RoundedSuperellipseBorder faceThumbnailSquircleBorder({
  required double side,
  BorderSide borderSide = BorderSide.none,
}) {
  return RoundedSuperellipseBorder(
    borderRadius: faceThumbnailSquircleBorderRadius(side),
    side: borderSide,
  );
}

Path faceThumbnailSquircleOuterPath(Size size) {
  final rect = Rect.fromLTWH(0, 0, size.width, size.height);
  final radius = faceThumbnailSquircleBorderRadius(size.shortestSide);
  return Path()..addRSuperellipse(radius.toRSuperellipse(rect));
}

class FaceThumbnailSquircleClip extends StatelessWidget {
  final Widget child;
  final BorderRadiusGeometry? borderRadius;

  const FaceThumbnailSquircleClip({
    required this.child,
    this.borderRadius,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    if (borderRadius != null) {
      return ClipRSuperellipse(borderRadius: borderRadius!, child: child);
    }

    return ClipRSuperellipse(
      clipper: const _FaceThumbnailSquircleClipper(),
      child: child,
    );
  }
}

class _FaceThumbnailSquircleClipper extends CustomClipper<RSuperellipse> {
  const _FaceThumbnailSquircleClipper();

  @override
  RSuperellipse getClip(Size size) {
    final rect = Offset.zero & size;
    final radius = faceThumbnailSquircleBorderRadius(size.shortestSide);
    return radius.toRSuperellipse(rect);
  }

  @override
  bool shouldReclip(_FaceThumbnailSquircleClipper oldClipper) => false;
}
