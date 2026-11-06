import "dart:math";

import "package:flutter/material.dart";
import "package:photos/ui/rewind/shell/rewind_page.dart";
import "package:photos/ui/rewind/theme/rewind_assets.dart";
import "package:photos/ui/rewind/theme/rewind_text_styles.dart";
import "package:photos/ui/rewind/widgets/rewind_backdrop.dart";
import "package:photos/ui/rewind/widgets/rewind_entrance.dart";
import "package:photos/ui/rewind/widgets/rewind_rive.dart";
import "package:photos/ui/rewind/widgets/rewind_stage.dart";
import "package:photos/ui/rewind/widgets/rewind_stickers.dart";
import "package:photos/ui/rewind/widgets/rewind_text.dart";

class SetupHeadline {
  const SetupHeadline(
    this.text, {
    required this.at,
    required this.size,
    this.height = 0.95,
    this.width = 342,
    this.turn = 0,
    this.delayMs = 0,
  });

  final String text;
  final Offset at;
  final double size;
  final double height;
  final double width;
  final double turn;
  final int delayMs;
}

class SetupCallout {
  const SetupCallout(
    this.text, {
    required this.center,
    this.turn = 3,
    this.size = 38.72,
    this.delayMs = 550,
    this.onTop = false,
  });

  final String text;
  final Offset center;
  final double turn;
  final double size;
  final int delayMs;
  final bool onTop;
}

class SetupArt {
  const SetupArt.ducky(
    this.asset,
    this.rect, {
    this.ticks = const [],
    this.pivot,
    this.delayMs = 760,
  }) : preset = RewindPreset.duck,
       animated = true;

  const SetupArt.image(
    this.asset,
    this.rect, {
    this.ticks = const [],
    this.pivot,
    this.delayMs = 760,
    this.preset = RewindPreset.duck,
  }) : animated = false;

  final String asset;
  final Rect rect;
  final List<(RewindTick, Rect)> ticks;
  final Offset? pivot;
  final int delayMs;
  final RewindPreset preset;
  final bool animated;
}

class SetupPage extends RewindPage {
  const SetupPage({
    required this.key,
    required this.color,
    required this.pattern,
    required this.ink,
    required this.headlines,
    required this.callout,
    required this.art,
    this.chrome = RewindChrome.light,
  });

  @override
  final String key;
  @override
  final RewindChrome chrome;
  final Color color;
  final Color pattern;
  final Color ink;
  final List<SetupHeadline> headlines;
  final SetupCallout callout;
  final SetupArt art;

  @override
  Widget build(
    BuildContext context,
    double position, {
    required bool isActive,
  }) {
    final calloutLayer = _callout(position, isActive);
    return Stack(
      fit: StackFit.expand,
      children: [
        RewindBackdrop(color: color, pattern: RewindZigzag(pattern)),
        RewindStage(
          children: [
            for (final headline in headlines)
              _headline(headline, position, isActive),
            if (!callout.onTop) calloutLayer,
            _art(position, isActive),
            if (callout.onTop) calloutLayer,
          ],
        ),
      ],
    );
  }

  Widget _headline(SetupHeadline headline, double position, bool isActive) {
    final style = RewindTextStyles.display(
      headline.size,
      color: ink,
      height: headline.height,
    );
    final lines = "\n".allMatches(headline.text).length + 1;
    return Positioned(
      left: headline.at.dx,
      top: headline.at.dy,
      child: RewindLeave(
        position: position,
        centerY: headline.at.dy + lines * headline.size * headline.height / 2,
        child: RewindEntrance(
          preset: RewindPreset.rise,
          active: isActive,
          delayMs: headline.delayMs,
          child: Transform.rotate(
            angle: headline.turn * pi / 180,
            alignment: Alignment.topLeft,
            child: RewindFitWidth(
              width: headline.width,
              child: Text(headline.text, style: style, softWrap: false),
            ),
          ),
        ),
      ),
    );
  }

  Widget _callout(double position, bool isActive) {
    const box = Size(380, 140);
    return Positioned.fromRect(
      rect: Rect.fromCenter(
        center: callout.center,
        width: box.width,
        height: box.height,
      ),
      child: RewindLeave(
        position: position,
        centerY: callout.center.dy,
        child: Center(
          child: RewindEntrance(
            preset: RewindPreset.pop,
            active: isActive,
            delayMs: callout.delayMs,
            child: Transform.rotate(
              angle: callout.turn * pi / 180,
              child: RewindFitWidth(
                width: box.width - 20,
                alignment: Alignment.center,
                child: RewindCallout(callout.text, size: callout.size),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _art(double position, bool isActive) {
    final pivot = art.pivot ?? art.rect.bottomCenter;
    return Positioned.fill(
      child: RewindLeave(
        position: position,
        centerY: art.rect.center.dy,
        child: RewindEntrance(
          preset: art.preset,
          active: isActive,
          delayMs: art.delayMs,
          origin: RewindStage.alignmentOf(pivot),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fromRect(
                rect: art.rect,
                child: art.animated
                    ? RewindDucky(art.asset)
                    : Image.file(
                        RewindAssets.file(art.asset),
                        fit: BoxFit.contain,
                      ),
              ),
              for (final (tick, rect) in art.ticks)
                Positioned.fromRect(rect: rect, child: RewindTickMark(tick)),
            ],
          ),
        ),
      ),
    );
  }
}
