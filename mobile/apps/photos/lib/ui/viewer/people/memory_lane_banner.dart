import "dart:typed_data";

import "package:collection/collection.dart";
import "package:flutter/material.dart";
import "package:logging/logging.dart";
import "package:photos/db/files_db.dart";
import "package:photos/db/ml/db.dart";
import "package:photos/l10n/l10n.dart";
import "package:photos/models/memory_lane/memory_lane_models.dart";
import "package:photos/models/ml/face/face.dart";
import "package:photos/models/ml/face/person.dart";
import "package:photos/services/memory_lane/memory_lane_service.dart";
import "package:photos/theme/ente_theme.dart";
import "package:photos/ui/components/menu_item_widget/menu_item_widget_new.dart";
import "package:photos/utils/face/face_thumbnail_cache.dart";

class MemoryLaneBanner extends StatelessWidget {
  final String title;
  final VoidCallback onTap;
  final ImageProvider? thumbnail;

  const MemoryLaneBanner({
    required this.title,
    required this.onTap,
    this.thumbnail,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = getEnteColorScheme(context);
    final backgroundColor = colorScheme.fill;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: MenuItemWidgetNew(
        title: title,
        titleMaxLines: 1,
        titleColor: colorScheme.textBase,
        leadingIconSize: 56,

        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        leadingIconWidget: _FaceThumbnail(
          image: thumbnail,
          backgroundColor: backgroundColor,
        ),

        trailingIcon: Icons.chevron_right,

        trailingIconColor: colorScheme.textBase,
        menuItemColor: backgroundColor,
        onTap: () async => onTap(),
      ),
    );
  }
}

class _FaceThumbnail extends StatelessWidget {
  final ImageProvider? image;
  final Color backgroundColor;

  const _FaceThumbnail({this.image, required this.backgroundColor});

  @override
  Widget build(BuildContext context) {
    final colorScheme = getEnteColorScheme(context);
    const double size = 56;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: colorScheme.fillFaint,
              borderRadius: BorderRadius.circular(18),
            ),
            clipBehavior: Clip.hardEdge,
            child: image != null
                ? Image(image: image!, fit: BoxFit.cover)
                : Center(
                    child: Icon(
                      Icons.person_outline,
                      color: colorScheme.textMuted,
                      size: 26,
                    ),
                  ),
          ),
          Positioned(
            top: -6,
            right: -6,
            child: _SparkleBadge(backgroundColor: backgroundColor),
          ),
        ],
      ),
    );
  }
}

class _SparkleBadge extends StatelessWidget {
  final Color backgroundColor;

  const _SparkleBadge({required this.backgroundColor});

  @override
  Widget build(BuildContext context) {
    const double targetSize = 18;
    const double strokeWidth = 4;
    return CustomPaint(
      size: const Size.square(targetSize + strokeWidth),
      painter: _SparklePainter(
        strokeColor: backgroundColor,
        fillColor: const Color(0xFF08C225),
        strokeWidth: strokeWidth,
      ),
    );
  }
}

const double _sparkleViewBoxSize = 32;

Path _buildSparklePath() {
  return Path()
    ..moveTo(18.8542, 28.494)
    ..lineTo(17.8702, 30.7562)
    ..cubicTo(17.7164, 31.1245, 17.457, 31.4392, 17.1246, 31.6606)
    ..cubicTo(16.7921, 31.8819, 16.4016, 32, 16.0022, 32)
    ..cubicTo(15.6027, 32, 15.2122, 31.8819, 14.8798, 31.6606)
    ..cubicTo(14.5474, 31.4392, 14.2879, 31.1245, 14.1342, 30.7562)
    ..lineTo(13.1501, 28.494)
    ..cubicTo(11.4201, 24.492, 8.25163, 21.2833, 4.27007, 19.501)
    ..lineTo(1.23405, 18.1461)
    ..cubicTo(0.865725, 17.9768, 0.553699, 17.7055, 0.334975, 17.3644)
    ..cubicTo(0.116251, 17.0233, 0, 16.6267, 0, 16.2216)
    ..cubicTo(0, 15.8165, 0.116251, 15.4199, 0.334975, 15.0788)
    ..cubicTo(0.553699, 14.7377, 0.865725, 14.4664, 1.23405, 14.2971)
    ..lineTo(4.10207, 13.0221)
    ..cubicTo(8.18372, 11.1891, 11.4064, 7.86168, 13.1061, 3.7254)
    ..lineTo(14.1182, 1.28332)
    ..cubicTo(14.2668, 0.905029, 14.526, 0.580261, 14.8621, 0.351349)
    ..cubicTo(15.1982, 0.122436, 15.5954, 0, 16.0022, 0)
    ..cubicTo(16.4089, 0, 16.8062, 0.122436, 17.1422, 0.351349)
    ..cubicTo(17.4783, 0.580261, 17.7375, 0.905029, 17.8862, 1.28332)
    ..lineTo(18.8982, 3.7214)
    ..cubicTo(20.5962, 7.85846, 23.8174, 11.1873, 27.8983, 13.0221)
    ..lineTo(30.7703, 14.3011)
    ..cubicTo(31.1375, 14.4709, 31.4484, 14.7421, 31.6663, 15.0828)
    ..cubicTo(31.8842, 15.4234, 32, 15.8193, 32, 16.2236)
    ..cubicTo(32, 16.6279, 31.8842, 17.0237, 31.6663, 17.3644)
    ..cubicTo(31.4484, 17.7051, 31.1375, 17.9763, 30.7703, 18.1461)
    ..lineTo(27.7303, 19.497)
    ..cubicTo(23.7495, 21.2811, 20.5825, 24.4912, 18.8542, 28.494)
    ..close();
}

final Path _sparklePath = _buildSparklePath();

class _SparklePainter extends CustomPainter {
  final Color strokeColor;
  final Color fillColor;
  final double strokeWidth;

  const _SparklePainter({
    required this.strokeColor,
    required this.fillColor,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final double contentSize = size.shortestSide - strokeWidth;
    final double scale = contentSize / _sparkleViewBoxSize;
    final Offset origin = Offset(
      (size.width - contentSize) / 2,
      (size.height - contentSize) / 2,
    );

    canvas.save();
    canvas.translate(origin.dx, origin.dy);
    canvas.scale(scale);

    final Paint strokePaint = Paint()
      ..color = strokeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth / scale
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;

    final Paint fillPaint = Paint()
      ..color = fillColor
      ..style = PaintingStyle.fill;

    canvas.drawPath(_sparklePath, strokePaint);
    canvas.drawPath(_sparklePath, fillPaint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _SparklePainter oldDelegate) {
    return oldDelegate.strokeColor != strokeColor ||
        oldDelegate.fillColor != fillColor ||
        oldDelegate.strokeWidth != strokeWidth;
  }
}

class MemoryLaneBannerSection extends StatefulWidget {
  final bool showBanner;
  final PersonEntity person;
  final VoidCallback? onTap;
  final Future<MemoryLanePersonTimeline?> Function(String personId)?
  loadTimeline;

  const MemoryLaneBannerSection({
    required this.showBanner,
    required this.person,
    this.onTap,
    this.loadTimeline,
    super.key,
  });

  @override
  State<MemoryLaneBannerSection> createState() =>
      _MemoryLaneBannerSectionState();
}

class _MemoryLaneBannerSectionState extends State<MemoryLaneBannerSection> {
  final Logger _logger = Logger("MemoryLaneBannerSection");
  MemoryImage? _thumbnail;
  Future<void>? _thumbnailFuture;
  bool _thumbnailResolved = false;

  @override
  void initState() {
    super.initState();
    _maybeLoadThumbnail();
  }

  @override
  void didUpdateWidget(covariant MemoryLaneBannerSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    final bool personChanged =
        widget.person.remoteID != oldWidget.person.remoteID;
    final bool bannerActivated =
        widget.showBanner && !oldWidget.showBanner && widget.onTap != null;
    final bool tapEnabled =
        widget.onTap != null && oldWidget.onTap == null && widget.showBanner;
    if (personChanged || bannerActivated || tapEnabled) {
      _thumbnail = null;
      _thumbnailFuture = null;
      _thumbnailResolved = false;
    }
    _maybeLoadThumbnail();
  }

  void _maybeLoadThumbnail() {
    if (!widget.showBanner || widget.onTap == null) {
      return;
    }
    _thumbnailFuture ??= _loadThumbnail();
  }

  Future<void> _loadThumbnail() async {
    try {
      final loader =
          widget.loadTimeline ?? MemoryLaneService.instance.getTimeline;
      final timeline = await loader(widget.person.remoteID);
      if (!mounted || timeline == null || !timeline.isReady) {
        _markThumbnailResolved();
        return;
      }
      if (timeline.entries.isEmpty) {
        _markThumbnailResolved();
        return;
      }
      final MemoryImage? image = await _loadFaceThumbnail(
        timeline.entries.first,
      );
      if (!mounted || image == null) {
        _markThumbnailResolved();
        return;
      }
      await precacheImage(image, context);
      if (!mounted) {
        return;
      }
      setState(() {
        _thumbnail = image;
        _thumbnailResolved = true;
      });
    } catch (error, stackTrace) {
      _logger.warning(
        "Failed to load Memory Lane banner thumbnail for "
        "${widget.person.remoteID}",
        error,
        stackTrace,
      );
      _markThumbnailResolved();
    }
  }

  void _markThumbnailResolved() {
    if (!mounted || _thumbnailResolved) {
      return;
    }
    setState(() {
      _thumbnailResolved = true;
    });
  }

  Future<MemoryImage?> _loadFaceThumbnail(MemoryLaneEntry entry) async {
    final file = await FilesDB.instance.getAnyUploadedFile(entry.fileId);
    if (file == null) {
      return null;
    }
    final faces = await MLDataDB.instance.getFacesForGivenFileID(entry.fileId);
    final Face? face = faces?.firstWhereOrNull(
      (candidate) => candidate.faceID == entry.faceId,
    );
    if (face == null) {
      return null;
    }
    try {
      final Map<String, Uint8List>? cropMap = await getCachedFaceCrops(
        file,
        [face],
        useFullFile: true,
        useTempCache: false,
      );
      final Uint8List? bytes = cropMap?[face.faceID];
      if (bytes == null || bytes.isEmpty) {
        return null;
      }
      return MemoryImage(bytes);
    } catch (error, stackTrace) {
      _logger.warning(
        "Failed to fetch face crop for banner "
        "person=${widget.person.remoteID} entry=${entry.faceId}",
        error,
        stackTrace,
      );
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.showBanner || widget.onTap == null || !_thumbnailResolved) {
      return const SizedBox.shrink();
    }
    return MemoryLaneBanner(
      title: context.l10n.facesTimelineBannerTitle,
      onTap: widget.onTap!,
      thumbnail: _thumbnail,
    );
  }
}
