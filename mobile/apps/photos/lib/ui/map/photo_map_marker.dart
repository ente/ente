import "dart:math" as math;

import "package:flutter/material.dart";
import "package:photos/models/file/file.dart";
import "package:photos/theme/ente_theme.dart";
import "package:photos/ui/map/map_gallery_tile_badge.dart";
import "package:photos/ui/viewer/file/thumbnail_widget.dart";

class PhotoMapMarker extends StatelessWidget {
  static const _sideInset = 12.0;
  static const _topInset = 9.0;
  static const _pointerHeight = 5.0;
  static const _frameWidth = 2.0;

  final EnteFile file;
  final int count;

  const PhotoMapMarker({super.key, required this.file, required this.count});

  static const _bodySize = Size(64, 64);

  static Size get markerSize {
    const body = _bodySize;
    return Size(
      body.width + _sideInset * 2,
      body.height + _topInset + _pointerHeight,
    );
  }

  @override
  Widget build(BuildContext context) {
    const body = _bodySize;
    const radius = 13.0;
    final colors = getEnteColorScheme(context);
    final frameColor = colors.backgroundElevated2;

    return Stack(
      children: [
        Positioned.fill(
          child: CustomPaint(
            painter: _PhotoPinFramePainter(
              body: Rect.fromLTWH(
                _sideInset,
                _topInset,
                body.width,
                body.height,
              ),
              radius: radius,
              color: frameColor,
            ),
          ),
        ),
        Positioned(
          left: _sideInset + _frameWidth,
          top: _topInset + _frameWidth,
          width: body.width - _frameWidth * 2,
          height: body.height - _frameWidth * 2,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(radius - _frameWidth),
            child: ThumbnailWidget(file, rawThumbnail: true),
          ),
        ),
        if (count > 1)
          Positioned(
            top: 0,
            right: 0,
            child: Container(
              constraints: const BoxConstraints(minWidth: 24, minHeight: 22),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFDADADA)),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x1A000000),
                    blurRadius: 3,
                    offset: Offset(0, 1),
                  ),
                ],
              ),
              child: Text(
                MapGalleryTileBadge.formatNumber(count),
                textAlign: TextAlign.center,
                textScaler: TextScaler.noScaling,
                style: const TextStyle(
                  fontSize: 12,
                  height: 1.2,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF242424),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _PhotoPinFramePainter extends CustomPainter {
  static (Rect, double, Size)? _cachedGeometry;
  static Path? _cachedFrame;

  final Rect body;
  final double radius;
  final Color color;

  const _PhotoPinFramePainter({
    required this.body,
    required this.radius,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final geometry = (body, radius, size);
    if (_cachedGeometry != geometry) {
      _cachedFrame = _buildFrame(size);
      _cachedGeometry = geometry;
    }
    final frame = _cachedFrame!;
    canvas.drawShadow(frame, const Color(0x45000000), 3, false);
    canvas.drawPath(frame, Paint()..color = color);
  }

  Path _buildFrame(Size size) {
    final center = body.center.dx;
    const halfWidth = 6.0;
    const pointerRadius = 1.0;
    const curveRadius = Radius.circular(pointerRadius);
    final tangentHeight = size.height - body.bottom - pointerRadius * 2;
    final angle =
        math.atan2(tangentHeight, halfWidth) +
        math.asin(
          pointerRadius *
              2 /
              math.sqrt(halfWidth * halfWidth + tangentHeight * tangentHeight),
        );
    final tangentX = pointerRadius * math.sin(angle);
    final tangentY = pointerRadius * math.cos(angle);
    final pointer = Path()
      ..moveTo(center - halfWidth, body.bottom - 1)
      ..lineTo(center - halfWidth, body.bottom)
      ..arcToPoint(
        Offset(
          center - halfWidth + tangentX,
          body.bottom + pointerRadius - tangentY,
        ),
        radius: curveRadius,
      )
      ..lineTo(center - tangentX, size.height - pointerRadius + tangentY)
      ..arcToPoint(
        Offset(center + tangentX, size.height - pointerRadius + tangentY),
        radius: curveRadius,
        clockwise: false,
      )
      ..lineTo(
        center + halfWidth - tangentX,
        body.bottom + pointerRadius - tangentY,
      )
      ..arcToPoint(Offset(center + halfWidth, body.bottom), radius: curveRadius)
      ..lineTo(center + halfWidth, body.bottom - 1)
      ..close();
    return Path.combine(
      PathOperation.union,
      Path()..addRRect(RRect.fromRectAndRadius(body, Radius.circular(radius))),
      pointer,
    );
  }

  @override
  bool shouldRepaint(_PhotoPinFramePainter oldDelegate) =>
      body != oldDelegate.body ||
      radius != oldDelegate.radius ||
      color != oldDelegate.color;
}
