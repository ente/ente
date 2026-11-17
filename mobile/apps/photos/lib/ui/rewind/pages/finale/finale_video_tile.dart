import "dart:math";
import "dart:ui" as ui;

import "package:flutter/material.dart";
import "package:flutter/rendering.dart";
import "package:photos/ui/rewind/pages/finale/finale_reel_preview.dart";
import "package:photos/ui/rewind/reel/rewind_video_export.dart";

class FinaleVideoTile extends StatefulWidget {
  const FinaleVideoTile({required this.active, super.key});

  static const _width = 168.0;
  static const _inset = 6.0;
  static const size = Size(_width, (_width - 2 * _inset) * 16 / 9 + 2 * _inset);

  final bool active;

  @override
  State<FinaleVideoTile> createState() => _FinaleVideoTileState();
}

class _FinaleVideoTileState extends State<FinaleVideoTile> {
  static const _tilt = -3 * pi / 180;
  static const _radius = 18.0;
  static const _shadow = Offset(5, 6);
  static const _coverInset = 14.0;

  final _content = GlobalKey();
  ui.Image? _frozen;

  @override
  void dispose() {
    _frozen?.dispose();
    super.dispose();
  }

  ui.Image? _freeze(double growth) {
    final boundary = _content.currentContext?.findRenderObject();
    if (boundary is! RenderRepaintBoundary) return null;
    _frozen?.dispose();
    return _frozen = boundary.toImageSync(
      pixelRatio: MediaQuery.devicePixelRatioOf(context) * growth,
    );
  }

  Widget _flight(
    BuildContext context,
    Animation<double> animation,
    HeroFlightDirection direction,
    BuildContext fromHero,
    BuildContext toHero,
  ) {
    final pushing = direction == HeroFlightDirection.push;
    final tile = (pushing ? fromHero : toHero).findRenderObject()! as RenderBox;
    final export =
        (pushing ? toHero : fromHero).findRenderObject()! as RenderBox;
    final frozen = pushing
        ? _freeze(export.size.width / tile.size.width)
        : null;
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final t = animation.value;
        double lerp(double from, double to) => ui.lerpDouble(from, to, t)!;
        return Transform.rotate(
          angle: lerp(_tilt, RewindVideoExportPage.previewTilt),
          child: FittedBox(
            fit: BoxFit.fill,
            child: SizedBox.fromSize(
              size: Size.lerp(tile.size, export.size, t),
              child: RewindVideoFrame(
                inset: lerp(
                  FinaleVideoTile._inset,
                  RewindVideoFrame.standardInset,
                ),
                radius: lerp(_radius, RewindVideoFrame.standardRadius),
                shadow: Offset.lerp(
                  _shadow,
                  RewindVideoFrame.standardShadow,
                  t,
                )!,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    RewindVideoCover(
                      inset: lerp(_coverInset, RewindVideoCover.standardInset),
                    ),
                    if (frozen != null)
                      Opacity(
                        opacity: (1 - t / 0.7).clamp(0.0, 1.0),
                        child: RawImage(image: frozen, fit: BoxFit.cover),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Hero(
      tag: RewindVideoExportPage.previewHeroTag,
      flightShuttleBuilder: _flight,
      child: Transform.rotate(
        angle: _tilt,
        child: SizedBox.fromSize(
          size: FinaleVideoTile.size,
          child: RewindVideoFrame(
            inset: FinaleVideoTile._inset,
            radius: _radius,
            shadow: _shadow,
            child: RepaintBoundary(
              key: _content,
              child: FinaleReelPreview(
                active: widget.active,
                coverInset: _coverInset,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
