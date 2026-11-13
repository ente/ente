import "dart:math";

import "package:flutter/material.dart";
import "package:photos/models/file/file.dart";
import "package:photos/services/rewind/rewind_edition.dart";
import "package:photos/src/rust/api/rewind_api.dart" as rust;
import "package:photos/ui/rewind/shell/rewind_page.dart";
import "package:photos/ui/rewind/shell/rewind_share.dart";
import "package:photos/ui/rewind/theme/rewind_colors.dart";
import "package:photos/ui/rewind/theme/rewind_motion.dart";
import "package:photos/ui/rewind/theme/rewind_text_styles.dart";
import "package:photos/ui/rewind/widgets/rewind_backdrop.dart";
import "package:photos/ui/rewind/widgets/rewind_elapsed.dart";
import "package:photos/ui/rewind/widgets/rewind_entrance.dart";
import "package:photos/ui/rewind/widgets/rewind_numbers.dart";
import "package:photos/ui/rewind/widgets/rewind_photo.dart";
import "package:photos/ui/rewind/widgets/rewind_photo_frames.dart";
import "package:photos/ui/rewind/widgets/rewind_reveal_layer.dart";
import "package:photos/ui/rewind/widgets/rewind_stage.dart";
import "package:photos/ui/rewind/widgets/rewind_text.dart";

const _months = [
  "January",
  "February",
  "March",
  "April",
  "May",
  "June",
  "July",
  "August",
  "September",
  "October",
  "November",
  "December",
];

String _ordinal(int day) {
  final teen = day % 100 >= 11 && day % 100 <= 13;
  final suffix = teen
      ? "th"
      : switch (day % 10) {
          1 => "st",
          2 => "nd",
          3 => "rd",
          _ => "th",
        };
  return "$day$suffix";
}

class BusiestDayPage extends RewindPage {
  const BusiestDayPage(this.day, this.photos);

  final rust.BusiestDay day;
  final List<EnteFile> photos;

  @override
  String get key => "busiest_day";

  @override
  Widget build(
    BuildContext context,
    double position, {
    required bool isActive,
  }) {
    final month = _months[(day.month - 1).clamp(0, 11)];
    final onDay = "On ${_ordinal(day.day)} $month";
    final kicker = "$onDay, you took";
    final count = rewindCount(day.photoCount);
    const line = "A memorable day indeed!";
    final date = "${day.day} ${month.substring(0, 3)} ${RewindEdition.year}"
        .toUpperCase();
    final split = photos.length >= 4;
    final upper = split
        ? [for (var i = 0; i < photos.length; i += 2) photos[i]]
        : photos;
    final lower = split
        ? [for (var i = 1; i < photos.length; i += 2) photos[i]]
        : [...photos.skip(1), ...photos.take(1)];
    final covered = ModalRoute.of(context)?.isCurrent == false;
    return RewindShareable(
      child: _HoldToPause(
        builder: (context, held) => Stack(
          fit: StackFit.expand,
          children: [
            const RewindBackdrop(
              color: Color(0xFFF7601F),
              pattern: RewindStripes(Color(0xFFFF6B2B)),
              grain: 0.25,
            ),
            Semantics(
              label:
                  "$kicker ${rewindCounted(day.photoCount, "photo", "photos")}. "
                  "$line",
              child: ExcludeSemantics(
                child: RewindStage(
                  children: [
                    if (upper.isNotEmpty) ...[
                      _Reel(
                        photos: upper,
                        date: date,
                        firstFrame: 1,
                        center: const Offset(195, 218),
                        turn: -7,
                        direction: 1,
                        delayMs: 60,
                        position: position,
                        isActive: isActive && !held && !covered,
                      ),
                      _Reel(
                        photos: lower,
                        date: date,
                        firstFrame: upper.length + 1,
                        center: const Offset(230.9, 436.8),
                        turn: 7,
                        direction: -1,
                        delayMs: 180,
                        position: position,
                        isActive: isActive && !held && !covered,
                      ),
                    ],
                    RewindRevealLayer(
                      left: 28,
                      top: 571,
                      maxWidth: 334,
                      height: 23,
                      position: position,
                      active: isActive,
                      delayMs: 900,
                      child: RewindVoice(
                        you: kicker.toUpperCase(),
                        me: "$onDay, I took".toUpperCase(),
                        builder: (text) => Text(
                          text,
                          style: RewindTextStyles.display(
                            20,
                            height: 1.15,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
                    ),
                    RewindRevealLayer(
                      left: 28,
                      top: 607,
                      maxWidth: 334,
                      height: 99,
                      position: position,
                      active: isActive,
                      preset: RewindPreset.slap,
                      delayMs: 1050,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          RewindOutlinedText(
                            count,
                            style: RewindTextStyles.numeral(
                              104,
                              color: RewindColors.white,
                            ),
                            outline: 3.5,
                            shadow: const Offset(5, 6),
                          ),
                          const SizedBox(width: 12),
                          RewindOutlinedText(
                            day.photoCount == 1 ? "PHOTO" : "PHOTOS",
                            style: RewindTextStyles.display(
                              44,
                              color: RewindColors.white,
                            ),
                            outline: 2.5,
                            shadow: const Offset(2.5, 3),
                          ),
                        ],
                      ),
                    ),
                    RewindRevealLayer(
                      left: 28,
                      top: 718,
                      width: 316,
                      height: 25,
                      position: position,
                      active: isActive,
                      delayMs: 1350,
                      child: Text(
                        line,
                        style: RewindTextStyles.body(19, height: 1.32),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HoldToPause extends StatefulWidget {
  const _HoldToPause({required this.builder});

  final Widget Function(BuildContext context, bool held) builder;

  @override
  State<_HoldToPause> createState() => _HoldToPauseState();
}

class _HoldToPauseState extends State<_HoldToPause> {
  var _pointers = 0;

  void _press(PointerDownEvent event) => setState(() => _pointers++);

  void _release(PointerEvent event) =>
      setState(() => _pointers = max(0, _pointers - 1));

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _press,
      onPointerUp: _release,
      onPointerCancel: _release,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onLongPress: () {},
        child: widget.builder(context, _pointers > 0),
      ),
    );
  }
}

class _Reel extends StatelessWidget {
  const _Reel({
    required this.photos,
    required this.date,
    required this.firstFrame,
    required this.center,
    required this.turn,
    required this.direction,
    required this.delayMs,
    required this.position,
    required this.isActive,
  });

  static const _length = 980.0;
  static const _pixelsPerMs = 1392 / 13000;
  static const _reach = 1650.0;
  static const _entryOffset = 560.0;

  final List<EnteFile> photos;
  final String date;
  final int firstFrame;
  final Offset center;
  final double turn;
  final int direction;
  final int delayMs;
  final double position;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final segment = 3 + photos.length * RewindFilmStrip.pitch;
    final before = (_reach / segment).ceil();
    final film = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var copy = 0; copy < 2 * before + 1; copy++)
          RewindFilmStrip(
            date: date,
            firstFrame: firstFrame,
            photos: [
              for (final file in photos)
                RewindPhoto(file, placeholder: const Color(0x1F151515)),
            ],
          ),
      ],
    );
    return Positioned.fromRect(
      rect: Rect.fromCenter(
        center: center,
        width: _length,
        height: RewindFilmStrip.height,
      ),
      child: RewindLeave(
        position: position,
        centerY: center.dy,
        child: Transform.rotate(
          angle: turn * pi / 180,
          child: OverflowBox(
            alignment: Alignment.centerLeft,
            maxWidth: double.infinity,
            child: RewindElapsed(
              active: isActive,
              stillMs: 2000,
              builder: (context, ms) {
                final entry = rewindProgress(
                  ms,
                  delayMs: delayMs.toDouble(),
                  durationMs: 1300,
                  curve: RewindMotion.expo,
                );
                final roll = direction * (ms * _pixelsPerMs % segment);
                final shift =
                    -before * segment +
                    roll -
                    direction * _entryOffset * (1 - entry);
                return Transform.translate(
                  offset: Offset(shift, 0),
                  child: film,
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
