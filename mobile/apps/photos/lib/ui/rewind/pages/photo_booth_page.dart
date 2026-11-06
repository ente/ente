import "dart:async";
import "dart:math";

import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:flutter_svg/flutter_svg.dart";
import "package:photos/models/file/file.dart";
import "package:photos/ui/rewind/shell/rewind_page.dart";
import "package:photos/ui/rewind/shell/rewind_share.dart";
import "package:photos/ui/rewind/story/rewind_face.dart";
import "package:photos/ui/rewind/theme/rewind_assets.dart";
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

class PhotoBoothPage extends RewindPage {
  const PhotoBoothPage({
    required this.person,
    required this.count,
    required this.photos,
    this.focus = const {},
  });

  static const pageKey = "people_booth";

  final RewindFace person;
  final int count;
  final List<EnteFile> photos;
  final Map<EnteFile, Alignment> focus;

  @override
  String get key => pageKey;

  @override
  Widget build(
    BuildContext context,
    double position, {
    required bool isActive,
  }) {
    final name = (person.name ?? "").toUpperCase();
    return RewindShareable(
      child: Stack(
        fit: StackFit.expand,
        children: [
          const RewindBackdrop(
            color: Color(0xFF9841E3),
            pattern: RewindStripes(Color(0xFF9D4EE0)),
          ),
          RewindStage(
            children: [
              Positioned.fill(
                child: RewindLeave(
                  position: position,
                  centerY: 330,
                  child: _Booth(photos: photos, focus: focus, active: isActive),
                ),
              ),
              RewindLayer(
                rect: const Rect.fromLTWH(278, 489, 77.8, 76.1),
                position: position,
                child: RewindEntrance(
                  preset: RewindPreset.bubble,
                  active: isActive,
                  delayMs: _Booth.printedMs,
                  child: Transform.rotate(
                    angle: -7 * pi / 180,
                    child: SvgPicture.file(
                      RewindAssets.file(RewindAssets.heartEyesSmiley),
                    ),
                  ),
                ),
              ),
              RewindLayer(
                rect: const Rect.fromLTWH(24, 601, 300, 24),
                position: position,
                child: RewindEntrance(
                  preset: RewindPreset.line,
                  active: isActive,
                  delayMs: 150,
                  child: Text(
                    "YOUR NO. 1",
                    style: RewindTextStyles.display(20, letterSpacing: 0.3),
                  ),
                ),
              ),
              RewindLayer(
                rect: const Rect.fromLTWH(24, 620, 340, 80),
                position: position,
                child: Align(
                  alignment: Alignment.topLeft,
                  child: RewindFitWidth(
                    width: 320,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 8, right: 28),
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          RewindEntrance(
                            preset: RewindPreset.slap,
                            active: isActive,
                            delayMs: 300,
                            origin: Alignment.centerLeft,
                            child: RewindOutlinedText(
                              name,
                              style: RewindTextStyles.display(
                                74,
                                color: RewindColors.yellow,
                                height: 0.9,
                                letterSpacing: -2.22,
                              ),
                              outline: 4,
                              shadow: const Offset(2.642, 3.171),
                            ),
                          ),
                          Positioned(
                            right: -28,
                            top: -8,
                            width: 42.5,
                            height: 42.5,
                            child: RewindKeyframes(
                              active: isActive,
                              delayMs: 1400,
                              durationMs: 520,
                              curve: const Cubic(0.2, 0.9, 0.3, 1.4),
                              hiddenBeforeStart: true,
                              poses: const [
                                RewindPose(0, scale: 0, turn: -30),
                                RewindPose(0.6, scale: 1.2, turn: 8),
                                RewindPose(1),
                              ],
                              child: SvgPicture.file(
                                RewindAssets.file(RewindAssets.pinkHeart),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              RewindLayer(
                rect: const Rect.fromLTWH(24, 704, 208, 52),
                position: position,
                child: RewindEntrance(
                  preset: RewindPreset.line,
                  active: isActive,
                  delayMs: 450,
                  child: Text(
                    "${rewindCounted(count, "photo", "photos")} together this "
                    "year. Here are a few.",
                    style: RewindTextStyles.body(18),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Booth extends StatefulWidget {
  const _Booth({
    required this.photos,
    required this.focus,
    required this.active,
  });

  static const printedMs = _printStartMs + _printMs;
  static const _printStartMs = 750;
  static const _printMs = 2600;

  final List<EnteFile> photos;
  final Map<EnteFile, Alignment> focus;
  final bool active;

  @override
  State<_Booth> createState() => _BoothState();
}

class _BoothState extends State<_Booth> with SingleTickerProviderStateMixin {
  static const _slot = Rect.fromLTWH(58, 96, 274, 46);
  static const _strip = Rect.fromLTWH(83, 118, 224, 451);
  static const _stops = [116.0, 226.0, 336.0, 451.0];
  static const _swayMs = 1300;
  static const _move = Cubic(0.4, 0, 0.3, 1);
  static const _drop = Cubic(0.2, 0.8, 0.3, 1);

  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: _Booth.printedMs + _swayMs),
  );
  var _lastStop = -1;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_buzz);
    if (widget.active) _controller.forward();
  }

  @override
  void didUpdateWidget(_Booth oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && _controller.isDismissed) _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double get _elapsed =>
      _controller.value * _controller.duration!.inMilliseconds;

  void _buzz() {
    final stop = _printed(_elapsed).stop;
    if (stop > _lastStop) {
      _lastStop = stop;
      unawaited(HapticFeedback.lightImpact());
    }
  }

  ({double length, int stop}) _printed(double elapsed) {
    final t = ((elapsed - _Booth._printStartMs) / _Booth._printMs).clamp(
      0.0,
      1.0,
    );
    final span = t * _stops.length;
    final index = min(span.floor(), _stops.length - 1);
    final within = span - index;
    final from = index == 0 ? 0.0 : _stops[index - 1];
    final moving = (within / 0.66).clamp(0.0, 1.0);
    final length = from + (_stops[index] - from) * _move.transform(moving);
    return (length: length, stop: moving >= 1 ? index : index - 1);
  }

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.disableAnimationsOf(context);
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final elapsed = still ? double.infinity : _elapsed;
        final printing =
            elapsed > _Booth._printStartMs && elapsed < _Booth.printedMs;
        final jitter = printing
            ? ((elapsed / 90).floor().isEven ? 0.7 : -0.7)
            : 0.0;
        final drop = _drop.transform(((elapsed - 150) / 520).clamp(0.0, 1.0));
        final slotOffset = Offset(jitter, still ? 0 : _slotDrop(drop));
        final slotOpacity = still ? 1.0 : (drop / 0.7).clamp(0.0, 1.0);
        final length = still ? _strip.height : _printed(elapsed).length;
        final sway = _sway(elapsed - _Booth.printedMs);
        return Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fromRect(
              rect: _slot.shift(slotOffset),
              child: Opacity(opacity: slotOpacity, child: const _SlotBody()),
            ),
            Positioned(
              left: _strip.left - 20,
              top: _strip.top,
              width: _strip.width + 40,
              height: _strip.height + 30,
              child: ClipRect(
                child: Transform.translate(
                  offset: Offset(20, length - _strip.height),
                  child: Transform.rotate(
                    angle: sway * pi / 180,
                    alignment: Alignment.topCenter,
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: DecoratedBox(
                        decoration: const BoxDecoration(
                          boxShadow: [
                            BoxShadow(
                              color: Color(0x33000000),
                              blurRadius: 8,
                              offset: Offset(-2, 4),
                            ),
                          ],
                        ),
                        child: RewindBoothStrip(
                          photos: [
                            for (var i = 0; i < 4; i++)
                              if (widget.photos.isNotEmpty)
                                _photo(widget.photos[i % widget.photos.length]),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned.fromRect(
              rect: Rect.fromLTWH(
                _slot.left,
                _slot.top,
                _slot.width,
                28,
              ).shift(slotOffset),
              child: Opacity(opacity: slotOpacity, child: const _SlotLip()),
            ),
          ],
        );
      },
    );
  }

  Widget _photo(EnteFile file) =>
      RewindPhoto(file, focus: widget.focus[file] ?? Alignment.center);

  double _slotDrop(double t) {
    if (t < 0.7) return -90 + 94 * t / 0.7;
    return 4 - 4 * (t - 0.7) / 0.3;
  }

  double _sway(double sinceMs) {
    if (sinceMs <= 0 || sinceMs >= _swayMs) return 0;
    final t = Curves.easeOut.transform(sinceMs / _swayMs);
    const angles = [0.0, 1.4, -0.8, 0.0];
    final span = t * (angles.length - 1);
    final i = min(span.floor(), angles.length - 2);
    return angles[i] + (angles[i + 1] - angles[i]) * (span - i);
  }
}

class _SlotBody extends StatelessWidget {
  const _SlotBody();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: RewindColors.ink,
          width: 3,
          strokeAlign: BorderSide.strokeAlignOutside,
        ),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFF6F5F2), Color(0xFFDCDAD5)],
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x42000000),
            offset: Offset(0, 14),
            blurRadius: 26,
          ),
          BoxShadow(color: Color(0x14000000), offset: Offset(0, 3)),
        ],
      ),
      child: const Padding(
        padding: EdgeInsets.fromLTRB(37, 18, 37, 18),
        child: _Slit(),
      ),
    );
  }
}

class _SlotLip extends StatelessWidget {
  const _SlotLip();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFF6F5F2), Color(0xFFE9E7E3)],
        ),
      ),
      child: const Padding(
        padding: EdgeInsets.fromLTRB(20.9, 18, 20.9, 0),
        child: _Slit(),
      ),
    );
  }
}

class _Slit extends StatelessWidget {
  const _Slit();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF000000), Color(0xFF161616)],
          stops: [0, 0.5],
        ),
      ),
      child: const SizedBox(height: 10),
    );
  }
}
