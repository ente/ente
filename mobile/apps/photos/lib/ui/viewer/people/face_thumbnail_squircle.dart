import "dart:math" as math;

import "package:flutter/widgets.dart";
import "package:photos/ui/viewer/file/hero_image.dart";

// RSuperellipse radii above half the side collapse into a circle. This factor
// preserves the previous iOS-style squircle shape.
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

class FaceThumbnailSquircleClip extends StatefulWidget {
  final Widget child;
  final BorderRadiusGeometry? borderRadius;
  final String? heroTag;

  const FaceThumbnailSquircleClip({
    required this.child,
    this.borderRadius,
    this.heroTag,
    super.key,
  });

  @override
  State<FaceThumbnailSquircleClip> createState() =>
      _FaceThumbnailSquircleClipState();
}

class _FaceThumbnailSquircleClipState extends State<FaceThumbnailSquircleClip> {
  late final _heroChildKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    if (widget.heroTag != null) {
      return LayoutBuilder(
        builder: (context, constraints) => Hero(
          tag: widget.heroTag!,
          createRectTween: imageHeroRectTween,
          placeholderBuilder: imageHeroPlaceholderBuilder,
          transitionOnUserGestures: true,
          child: ClipRSuperellipse(
            key: _heroChildKey,
            borderRadius:
                widget.borderRadius ??
                faceThumbnailSquircleBorderRadius(
                  constraints.biggest.shortestSide,
                ),
            child: widget.child,
          ),
        ),
      );
    }
    if (widget.borderRadius != null) {
      return ClipRSuperellipse(
        borderRadius: widget.borderRadius!,
        child: widget.child,
      );
    }

    return ClipRSuperellipse(
      clipper: const _FaceThumbnailSquircleClipper(),
      child: widget.child,
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
