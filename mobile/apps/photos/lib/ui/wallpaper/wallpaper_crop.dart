import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

class WallpaperCrop {
  Offset _center = const Offset(0.5, 0.5);
  double _zoom = 1;
  Rect region = const Rect.fromLTWH(0, 0, 1, 1);

  void layout(Size viewport, ui.Image image) {
    final scale = _scale(viewport, image);
    final halfWidth = math.min(0.5, viewport.width / (2 * scale * image.width));
    final halfHeight = math.min(
      0.5,
      viewport.height / (2 * scale * image.height),
    );
    _center = Offset(
      _center.dx.clamp(halfWidth, 1 - halfWidth),
      _center.dy.clamp(halfHeight, 1 - halfHeight),
    );
    region = Rect.fromCenter(
      center: _center,
      width: 2 * halfWidth,
      height: 2 * halfHeight,
    );
  }

  void update(
    ScaleUpdateDetails details,
    double zoom,
    Size viewport,
    ui.Image image,
  ) {
    final before = _scale(viewport, image);
    _zoom = zoom.clamp(1, 4);
    final after = _scale(viewport, image);
    final focus = details.localFocalPoint - viewport.center(Offset.zero);
    final delta =
        focus * (1 / before - 1 / after) - details.focalPointDelta / before;
    _center += Offset(delta.dx / image.width, delta.dy / image.height);
    layout(viewport, image);
  }

  double _scale(Size viewport, ui.Image image) =>
      math.max(viewport.width / image.width, viewport.height / image.height) *
      _zoom;
}

class WallpaperCropView extends StatefulWidget {
  const WallpaperCropView({
    required this.image,
    required this.crop,
    required this.enabled,
    super.key,
  });

  final ui.Image image;
  final WallpaperCrop crop;
  final bool enabled;

  @override
  State<WallpaperCropView> createState() => _WallpaperCropViewState();
}

class _WallpaperCropViewState extends State<WallpaperCropView> {
  double _startZoom = 1;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewport = constraints.biggest;
        widget.crop.layout(viewport, widget.image);
        return GestureDetector(
          onScaleStart: widget.enabled
              ? (_) => _startZoom = widget.crop._zoom
              : null,
          onScaleUpdate: widget.enabled
              ? (details) => setState(() {
                  widget.crop.update(
                    details,
                    _startZoom * details.scale,
                    viewport,
                    widget.image,
                  );
                })
              : null,
          child: CustomPaint(
            painter: _CropPainter(widget.image, widget.crop.region),
            size: viewport,
          ),
        );
      },
    );
  }
}

class _CropPainter extends CustomPainter {
  const _CropPainter(this.image, this.region);

  final ui.Image image;
  final Rect region;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.black);
    canvas.drawImageRect(
      image,
      Rect.fromLTRB(
        region.left * image.width,
        region.top * image.height,
        region.right * image.width,
        region.bottom * image.height,
      ),
      Offset.zero & size,
      Paint()..filterQuality = FilterQuality.medium,
    );
  }

  @override
  bool shouldRepaint(_CropPainter oldDelegate) =>
      image != oldDelegate.image || region != oldDelegate.region;
}
