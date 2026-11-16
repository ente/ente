import "dart:async";
import "dart:math";

import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:photos/models/file/file.dart";
import "package:photos/ui/rewind/theme/rewind_colors.dart";
import "package:photos/ui/rewind/theme/rewind_text_styles.dart";
import "package:photos/ui/rewind/widgets/rewind_entrance.dart";
import "package:photos/ui/rewind/widgets/rewind_photo.dart";
import "package:photos/ui/rewind/widgets/rewind_photo_frames.dart";
import "package:photos/ui/rewind/widgets/rewind_stage.dart";
import "package:photos/ui/rewind/widgets/rewind_text.dart";

void showRewindPhotoGallery(
  BuildContext context, {
  required Widget header,
  required Size headerSize,
  required List<EnteFile> photos,
  String? title,
}) {
  unawaited(HapticFeedback.selectionClick());
  unawaited(
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: "Close",
      barrierColor: const Color(0xD9000000),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (context, _, _) => Material(
        type: MaterialType.transparency,
        child: _RewindPhotoGallery(
          header: header,
          headerSize: headerSize,
          title: title,
          photos: photos,
        ),
      ),
      transitionBuilder: (context, animation, _, child) => FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
        child: child,
      ),
    ),
  );
}

class _RewindPhotoGallery extends StatelessWidget {
  const _RewindPhotoGallery({
    required this.header,
    required this.headerSize,
    required this.photos,
    this.title,
  });

  static const _polaroid = Size(104, 124.4);
  static const _columns = 3;
  static const _columnGap = 116.0;
  static const _rowGap = 136.0;
  static const _turns = [-4.0, 3.0, -2.0, 2.5, -3.0, 4.0, -1.5, 2.0, -3.5];

  final Widget header;
  final Size headerSize;
  final String? title;
  final List<EnteFile> photos;

  @override
  Widget build(BuildContext context) {
    final title = this.title;
    final shown = min(photos.length, _turns.length);
    final gridTop = title == null ? 300.0 : 362.0;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.of(context).pop(),
      child: RewindStage(
        children: [
          Positioned.fromRect(
            rect: Rect.fromCenter(
              center: const Offset(195, 150),
              width: headerSize.width,
              height: headerSize.height,
            ),
            child: RewindEntrance(
              preset: RewindPreset.bubble,
              active: true,
              child: header,
            ),
          ),
          if (title != null)
            Positioned(
              left: 24,
              top: 226,
              child: RewindEntrance(
                preset: RewindPreset.slap,
                active: true,
                delayMs: 120,
                child: RewindFitWidth(
                  width: 342,
                  alignment: Alignment.center,
                  child: RewindOutlinedText(
                    title.toUpperCase(),
                    style: RewindTextStyles.display(
                      44,
                      color: RewindColors.white,
                    ),
                    outline: 2,
                    shadow: const Offset(2.4, 2.9),
                  ),
                ),
              ),
            ),
          for (var i = 0; i < shown; i++)
            Positioned.fromRect(
              rect: Rect.fromCenter(
                center: Offset(
                  195 + (i % _columns - 1) * _columnGap,
                  gridTop + (i ~/ _columns) * _rowGap,
                ),
                width: _polaroid.width,
                height: _polaroid.height,
              ),
              child: RewindEntrance(
                preset: RewindPreset.pop,
                active: true,
                delayMs: 180 + 60 * i,
                child: Transform.rotate(
                  angle: _turns[i] * pi / 180,
                  child: RewindPolaroid(
                    photo: RewindPhoto(photos[i]),
                    width: _polaroid.width,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
