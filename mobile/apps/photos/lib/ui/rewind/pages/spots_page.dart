import "dart:math";

import "package:flutter/material.dart";
import "package:photos/models/file/file.dart";
import "package:photos/src/rust/api/rewind_api.dart" as rust;
import "package:photos/ui/rewind/shell/rewind_page.dart";
import "package:photos/ui/rewind/shell/rewind_share.dart";
import "package:photos/ui/rewind/theme/rewind_colors.dart";
import "package:photos/ui/rewind/theme/rewind_text_styles.dart";
import "package:photos/ui/rewind/widgets/rewind_backdrop.dart";
import "package:photos/ui/rewind/widgets/rewind_entrance.dart";
import "package:photos/ui/rewind/widgets/rewind_keyframes.dart";
import "package:photos/ui/rewind/widgets/rewind_layer.dart";
import "package:photos/ui/rewind/widgets/rewind_numbers.dart";
import "package:photos/ui/rewind/widgets/rewind_photo.dart";
import "package:photos/ui/rewind/widgets/rewind_photo_frames.dart";
import "package:photos/ui/rewind/widgets/rewind_stage.dart";
import "package:photos/ui/rewind/widgets/rewind_text.dart";

class SpotsPage extends RewindPage {
  const SpotsPage(this.spots, this.photos);

  static const pageKey = "spots";

  static const _hero = (center: Offset(196.4, 361.6), turn: 2.0);
  static const _pile = [
    (center: Offset(78.6, 212.9), turn: 13.0),
    (center: Offset(195.7, 174.3), turn: -7.0),
    (center: Offset(316.5, 238.6), turn: -14.0),
    (center: Offset(65.7, 358.3), turn: 7.0),
    (center: Offset(183.8, 552.5), turn: 11.0),
    (center: Offset(322.7, 395.3), turn: -7.0),
    (center: Offset(74.8, 512.7), turn: -10.0),
    (center: Offset(295.8, 521.2), turn: 8.0),
  ];
  static const _fillOrder = [1, 4, 3, 5, 0, 7, 2, 6];
  static const _small = Size(112, 134);
  static const _large = Size(160.188, 191.654);

  final rust.Spots spots;
  final List<EnteFile> photos;

  @override
  String get key => pageKey;

  @override
  RewindChrome get chrome => RewindChrome.dark;

  @override
  Widget build(
    BuildContext context,
    double position, {
    required bool isActive,
  }) {
    final filled = {
      for (final (i, slot)
          in _fillOrder.take(max(0, photos.length - 1)).indexed)
        slot: photos[i + 1],
    };
    return RewindShareable(
      child: Stack(
        fit: StackFit.expand,
        children: [
          const RewindBackdrop(
            color: Color(0xFFFFCA39),
            pattern: RewindStripes(Color(0x66FFD24E)),
          ),
          RewindStage(
            children: [
              for (final (i, spot) in _pile.indexed)
                if (filled[i] case final photo?)
                  _polaroid(
                    spot.center,
                    _small,
                    position,
                    RewindKeyframes(
                      active: isActive,
                      delayMs: 700 + 35 * i,
                      durationMs: 820,
                      curve: const Cubic(0.22, 1, 0.36, 1),
                      poses: [
                        RewindPose(
                          0,
                          dx: _hero.center.dx - spot.center.dx,
                          dy: _hero.center.dy - spot.center.dy,
                          scale: 0.8,
                        ),
                        const RewindPose(1),
                      ],
                      child: RewindKeyframes(
                        active: isActive,
                        delayMs: 700 + 35 * i,
                        durationMs: 120,
                        hiddenBeforeStart: true,
                        poses: const [RewindPose(0, opacity: 0), RewindPose(1)],
                        child: _frame(photo, spot.turn, _small),
                      ),
                    ),
                  ),
              if (photos.isNotEmpty)
                _polaroid(
                  _hero.center,
                  _large,
                  position,
                  RewindKeyframes(
                    active: isActive,
                    delayMs: 250,
                    durationMs: 520,
                    curve: const Cubic(0.2, 0.8, 0.3, 1),
                    hiddenBeforeStart: true,
                    poses: const [
                      RewindPose(0, scale: 0.6, opacity: 0),
                      RewindPose(0.6, scale: 1.04),
                      RewindPose(1),
                    ],
                    child: _frame(photos.first, _hero.turn, _large),
                  ),
                ),
              RewindLayer(
                rect: const Rect.fromLTWH(28, 664, 334, 44),
                position: position,
                child: RewindEntrance(
                  preset: RewindPreset.rise,
                  active: isActive,
                  child: RewindFitWidth(
                    width: 334,
                    child: RewindOutlinedText(
                      "${rewindCount(spots.photoCount)} "
                      "${spots.photoCount == 1 ? "PHOTO" : "PHOTOS"}",
                      style: RewindTextStyles.display(
                        48.039,
                        color: RewindColors.white,
                        height: 0.84,
                        letterSpacing: -1.441,
                      ),
                      shadow: const Offset(1.766, 2.119),
                    ),
                  ),
                ),
              ),
              RewindLayer(
                rect: const Rect.fromLTWH(28, 718, 316, 48),
                position: position,
                child: RewindEntrance(
                  preset: RewindPreset.line,
                  active: isActive,
                  delayMs: 220,
                  child: Text(
                    "From ${rewindCounted(spots.spotCount, "spot", "spots")} "
                    "you keep going back to.",
                    style: RewindTextStyles.body(17, color: RewindColors.ink),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _polaroid(Offset center, Size size, double position, Widget child) {
    return RewindLayer(
      rect: Rect.fromCenter(
        center: center,
        width: size.width,
        height: size.height,
      ),
      position: position,
      child: child,
    );
  }

  Widget _frame(EnteFile photo, double turn, Size size) {
    return Transform.rotate(
      angle: turn * pi / 180,
      child: RewindPolaroid(photo: RewindPhoto(photo), width: size.width),
    );
  }
}
