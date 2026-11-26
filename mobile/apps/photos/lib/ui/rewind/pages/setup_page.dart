import "dart:math";

import "package:flutter/material.dart";
import "package:photos/models/file/file.dart";
import "package:photos/ui/rewind/copy/rewind_copy.dart";
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
  const SetupHeadline({
    required this.at,
    required this.size,
    this.height = 0.95,
    this.width = 342,
    this.turn = 0,
    this.delayMs = 0,
  });

  final Offset at;
  final double size;
  final double height;
  final double width;
  final double turn;
  final int delayMs;
}

class SetupCallout {
  const SetupCallout({
    required this.center,
    this.turn = 3,
    this.size = 38.72,
    this.delayMs = 550,
    this.onTop = false,
  });

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
    this.stateMachine = "Loop",
    this.ticks = const [],
    this.pivot,
    this.delayMs = 760,
  }) : preset = RewindPreset.duck;

  const SetupArt.image(
    this.asset,
    this.rect, {
    this.ticks = const [],
    this.pivot,
    this.delayMs = 760,
    this.preset = RewindPreset.duck,
  }) : stateMachine = null;

  final String asset;
  final Rect rect;
  final String? stateMachine;
  final List<(RewindTick, Rect)> ticks;
  final Offset? pivot;
  final int delayMs;
  final RewindPreset preset;

  bool get animated => stateMachine != null;
}

class SetupPage extends RewindPage {
  const SetupPage({
    required this.key,
    required this.setup,
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
  final RewindSetup setup;
  @override
  final RewindChrome chrome;
  final Color color;
  final Color pattern;
  final Color ink;
  final List<SetupHeadline> headlines;
  final SetupCallout callout;
  final SetupArt art;

  @override
  Duration? get reelHold => null;

  @override
  Duration? get clipHold => const Duration(milliseconds: 3000);

  @override
  List<EnteFile> get reelThumbnails => const [];

  @override
  Widget build(
    BuildContext context,
    double position, {
    required bool isActive,
  }) {
    final lines = RewindCopy.of(context).setup(setup);
    final fit = _headlineFit(lines.headlines, MediaQuery.textScalerOf(context));
    final calloutLayer = _callout(lines.callout, position, isActive);
    return Stack(
      fit: StackFit.expand,
      children: [
        RewindBackdrop(color: color, pattern: RewindZigzag(pattern)),
        RewindStage(
          children: [
            for (final (i, headline) in headlines.indexed)
              _headline(headline, lines.headlines[i], fit, position, isActive),
            if (!callout.onTop) calloutLayer,
            _art(position, isActive),
            if (callout.onTop) calloutLayer,
          ],
        ),
      ],
    );
  }

  TextStyle _headlineStyle(SetupHeadline headline, double fit) =>
      RewindTextStyles.display(
        headline.size * fit,
        color: ink,
        height: headline.height,
      );

  double _headlineFit(List<String> texts, TextScaler scaler) {
    var fit = 1.0;
    for (final (i, headline) in headlines.indexed) {
      final painter = TextPainter(
        text: TextSpan(text: texts[i], style: _headlineStyle(headline, 1)),
        textDirection: TextDirection.ltr,
        textScaler: scaler,
      )..layout();
      fit = min(fit, headline.width / painter.width);
      painter.dispose();
    }
    return fit;
  }

  Widget _headline(
    SetupHeadline headline,
    String text,
    double fit,
    double position,
    bool isActive,
  ) {
    final style = _headlineStyle(headline, fit);
    final lines = "\n".allMatches(text).length + 1;
    final origin = headlines.first.at.dy;
    final top = origin + (headline.at.dy - origin) * fit;
    return Positioned(
      left: headline.at.dx,
      top: top,
      child: RewindLeave(
        position: position,
        centerY: top + lines * headline.size * fit * headline.height / 2,
        child: RewindEntrance(
          preset: RewindPreset.rise,
          active: isActive,
          delayMs: headline.delayMs,
          child: Transform.rotate(
            angle: headline.turn * pi / 180,
            alignment: Alignment.topLeft,
            child: RewindFitWidth(
              width: headline.width,
              child: Text(text, style: style, softWrap: false),
            ),
          ),
        ),
      ),
    );
  }

  Widget _callout(String text, double position, bool isActive) {
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
                child: RewindCallout(text, size: callout.size),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _art(double position, bool isActive) {
    final pivot = art.pivot ?? art.rect.bottomCenter;
    final stack = Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fromRect(
          rect: art.rect,
          child: switch (art.stateMachine) {
            final stateMachine? => RewindDucky(
              art.asset,
              stateMachine: stateMachine,
            ),
            null => Image.file(
              RewindAssets.file(art.asset),
              fit: BoxFit.contain,
            ),
          },
        ),
        for (final (tick, rect) in art.ticks)
          Positioned.fromRect(rect: rect, child: RewindTickMark(tick)),
      ],
    );
    return Positioned.fill(
      child: RewindLeave(
        position: position,
        centerY: art.rect.center.dy,
        child: art.animated
            ? stack
            : RewindEntrance(
                preset: art.preset,
                active: isActive,
                delayMs: art.delayMs,
                origin: RewindStage.alignmentOf(pivot),
                child: stack,
              ),
      ),
    );
  }
}
