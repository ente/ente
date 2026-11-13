import "package:flutter/material.dart";
import "package:hugeicons/hugeicons.dart";
import "package:photos/models/file/file.dart";
import "package:photos/theme/ente_theme.dart";
import "package:photos/ui/viewer/file/thumbnail_widget.dart";

enum RitualDayThumbnailVariant { photo, empty, camera, future, hidden }

class RitualDayThumbnail extends StatelessWidget {
  const RitualDayThumbnail({
    required this.day,
    required this.variant,
    required this.width,
    this.photoFile,
    this.photoCount,
    this.fadePhoto = false,
    this.rotation = 0,
    this.onCameraTap,
    super.key,
  });

  final DateTime day;
  final RitualDayThumbnailVariant variant;
  final double width;

  final EnteFile? photoFile;
  final int? photoCount;

  final bool fadePhoto;
  final double rotation;
  final VoidCallback? onCameraTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = getEnteTextTheme(context);
    final tileHeight = width * (72 / 48);

    final label = "${_weekdayLabel(context, day)}\n${day.day}";
    return SizedBox(
      width: width,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          _Tile(
            width: width,
            height: tileHeight,
            variant: variant,
            photoFile: photoFile,
            photoCount: photoCount,
            fadePhoto: fadePhoto,
            rotation: rotation,
            onCameraTap: onCameraTap,
          ),
          const SizedBox(height: 8),
          Text(
            label,
            textAlign: TextAlign.center,
            textHeightBehavior: _tightTextHeightBehavior,
            style: textTheme.miniBoldMuted.copyWith(height: 1.05),
          ),
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.width,
    required this.height,
    required this.variant,
    required this.photoFile,
    required this.photoCount,
    required this.fadePhoto,
    required this.rotation,
    required this.onCameraTap,
  });

  final double width;
  final double height;
  final RitualDayThumbnailVariant variant;
  final EnteFile? photoFile;
  final int? photoCount;
  final bool fadePhoto;
  final double rotation;
  final VoidCallback? onCameraTap;

  static const _blueBorder = Color(0xFF1DA9FF);
  static const _blueFill = Color(0x231DA9FF);
  static const _greenBorder = Color(0xFF1DB954);
  static const _greenFill = Color(0x191DB954);
  static const _futureBorder = Color(0xFFD3D3D3);
  static const _futureFill = Color(0x1AD3D3D3);

  @override
  Widget build(BuildContext context) {
    return switch (variant) {
      RitualDayThumbnailVariant.photo => _PhotoTile(
        width: width,
        height: height,
        file: photoFile,
        count: photoCount ?? 0,
        fadePhoto: fadePhoto,
        rotation: rotation,
      ),
      RitualDayThumbnailVariant.empty => _DottedTile(
        width: width,
        height: height,
        borderColor: _blueBorder,
        fillColor: _blueFill,
      ),
      RitualDayThumbnailVariant.camera => _DottedTile(
        width: width,
        height: height,
        borderColor: _greenBorder,
        fillColor: _greenFill,
        child: IconButton(
          padding: EdgeInsets.zero,
          visualDensity: VisualDensity.compact,
          icon: const Icon(
            Icons.photo_camera_outlined,
            size: 21,
            color: _greenBorder,
          ),
          onPressed: onCameraTap,
        ),
      ),
      RitualDayThumbnailVariant.future => _DottedTile(
        width: width,
        height: height,
        borderColor: _futureBorder,
        fillColor: _futureFill,
      ),
      RitualDayThumbnailVariant.hidden => _HiddenTile(
        width: width,
        height: height,
      ),
    };
  }
}

class _HiddenTile extends StatelessWidget {
  const _HiddenTile({required this.width, required this.height});

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final colorScheme = getEnteColorScheme(context);
    return _DottedTile(
      width: width,
      height: height,
      borderColor: colorScheme.strokeFaint,
      fillColor: colorScheme.fillFaint,
      child: HugeIcon(
        icon: HugeIcons.strokeRoundedSquareLock01,
        size: 18,
        color: colorScheme.textMuted,
      ),
    );
  }
}

class _DottedTile extends StatelessWidget {
  const _DottedTile({
    required this.width,
    required this.height,
    required this.borderColor,
    required this.fillColor,
    this.child,
  });

  final double width;
  final double height;
  final Color borderColor;
  final Color fillColor;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: CustomPaint(
        painter: _DashedRRectBorderPainter(
          color: borderColor,
          strokeWidth: 1,
          dashLength: 4,
          dashGap: 3,
          radius: 8,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: ColoredBox(
            color: fillColor,
            child: Center(child: child),
          ),
        ),
      ),
    );
  }
}

class _PhotoTile extends StatelessWidget {
  const _PhotoTile({
    required this.width,
    required this.height,
    required this.file,
    required this.count,
    required this.fadePhoto,
    required this.rotation,
  });

  final double width;
  final double height;
  final EnteFile? file;
  final int count;
  final bool fadePhoto;
  final double rotation;

  @override
  Widget build(BuildContext context) {
    final colorScheme = getEnteColorScheme(context);
    final textTheme = getEnteTextTheme(context);

    return SizedBox(
      width: width,
      height: height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: Center(
              child: Transform.rotate(
                angle: rotation,
                child: Opacity(
                  opacity: fadePhoto ? 0.45 : 1.0,
                  child: Container(
                    width: width,
                    height: height,
                    decoration: BoxDecoration(
                      color: colorScheme.fillFaint,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white, width: 2),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x3F000000),
                          blurRadius: 5.3,
                          offset: Offset(2, 2),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: file == null
                          ? const SizedBox.shrink()
                          : ThumbnailWidget(
                              file!,
                              fit: BoxFit.cover,
                              rawThumbnail: true,
                              shouldShowSyncStatus: false,
                              shouldShowOwnerAvatar: false,
                              shouldShowFavoriteIcon: false,
                              shouldShowVideoDuration: false,
                              shouldShowVideoOverlayIcon: false,
                            ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (count > 1)
            Positioned(
              top: 6,
              right: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                decoration: BoxDecoration(
                  color: colorScheme.backgroundElevated,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  "$count",
                  style: textTheme.tinyBold.copyWith(
                    color: const Color(0xFF1DB954),
                  ),
                  textHeightBehavior: _tightTextHeightBehavior,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

String _weekdayLabel(BuildContext context, DateTime day) {
  switch (day.weekday) {
    case DateTime.monday:
      return "M";
    case DateTime.tuesday:
      return "Tu";
    case DateTime.wednesday:
      return "W";
    case DateTime.thursday:
      return "Th";
    case DateTime.friday:
      return "F";
    case DateTime.saturday:
      return "Sa";
    case DateTime.sunday:
      return "Su";
    default:
      final labels = MaterialLocalizations.of(context).narrowWeekdays;
      return labels[day.weekday % 7];
  }
}

const _tightTextHeightBehavior = TextHeightBehavior(
  applyHeightToFirstAscent: false,
  applyHeightToLastDescent: false,
);

class _DashedRRectBorderPainter extends CustomPainter {
  const _DashedRRectBorderPainter({
    required this.color,
    required this.strokeWidth,
    required this.dashLength,
    required this.dashGap,
    required this.radius,
  });

  final Color color;
  final double strokeWidth;
  final double dashLength;
  final double dashGap;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final inset = strokeWidth / 2;
    final rect = Rect.fromLTWH(
      inset,
      inset,
      (size.width - strokeWidth).clamp(0.0, double.infinity),
      (size.height - strokeWidth).clamp(0.0, double.infinity),
    );
    final rrect = RRect.fromRectAndRadius(
      rect,
      Radius.circular((radius - inset).clamp(0.0, radius)),
    );
    final path = Path()..addRRect(rrect);

    for (final metric in path.computeMetrics()) {
      double distance = 0;
      while (distance < metric.length) {
        final next = (distance + dashLength).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(distance, next), paint);
        distance = next + dashGap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedRRectBorderPainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.strokeWidth != strokeWidth ||
        oldDelegate.dashLength != dashLength ||
        oldDelegate.dashGap != dashGap ||
        oldDelegate.radius != radius;
  }
}
