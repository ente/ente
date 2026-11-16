import "dart:math";

import "package:flutter/material.dart";
import "package:photos/ui/rewind/shell/rewind_music.dart";
import "package:photos/ui/rewind/shell/rewind_page.dart";
import "package:photos/ui/rewind/theme/rewind_colors.dart";
import "package:photos/ui/rewind/theme/rewind_motion.dart";
import "package:photos/ui/rewind/widgets/rewind_buttons.dart";
import "package:photos/ui/rewind/widgets/rewind_stage.dart";
import "package:photos/ui/rewind/widgets/rewind_wordmark.dart";

class RewindChromeLayout {
  RewindChromeLayout(this.size, EdgeInsets padding)
    : bottom = max(12.0, padding.bottom),
      top = padding.top;

  static const buttonSize = 40.0;
  static const sideInset = 22.0;
  static const wordmarkSize = Size(50, 15);

  final Size size;
  final double bottom;
  final double top;

  Rect get wordmark => Rect.fromLTWH(
    (size.width - wordmarkSize.width) / 2,
    size.height - bottom - buttonSize / 2 - wordmarkSize.height / 2 + 2,
    wordmarkSize.width,
    wordmarkSize.height,
  );

  Offset get rail {
    final scale = RewindStage.scaleFor(size);
    return Offset(14 * scale, RewindStage.originFor(size).dy + 186 * scale);
  }
}

class RewindChromeOverlay extends StatelessWidget {
  const RewindChromeOverlay({
    required this.layout,
    required this.chrome,
    required this.page,
    required this.pageCount,
    required this.music,
    required this.onClose,
    required this.shareKey,
    required this.videoKey,
    this.onShare,
    this.onShareVideo,
    super.key,
  });

  final RewindChromeLayout layout;
  final RewindChrome chrome;
  final int page;
  final int pageCount;
  final RewindMusic music;
  final VoidCallback onClose;
  final GlobalKey shareKey;
  final GlobalKey videoKey;
  final VoidCallback? onShare;
  final VoidCallback? onShareVideo;

  @override
  Widget build(BuildContext context) {
    final wordmark = chrome.wordmark;
    return Stack(
      children: [
        Positioned(
          top: layout.top + 5,
          right: RewindChromeLayout.sideInset,
          child: RewindRoundButton(
            glyph: RewindGlyph.close,
            label: "Close",
            size: 36,
            ring: false,
            onTap: onClose,
          ),
        ),
        Positioned(
          right: layout.rail.dx,
          top: layout.rail.dy,
          child: RewindProgressRail(
            index: page,
            count: pageCount,
            color: chrome.foreground,
          ),
        ),
        if (chrome.muteButton)
          Positioned(
            left: RewindChromeLayout.sideInset,
            bottom: layout.bottom,
            child: ListenableBuilder(
              listenable: music,
              builder: (context, _) => RewindRoundButton(
                glyph: music.muted ? RewindGlyph.muted : RewindGlyph.sound,
                label: music.muted ? "Play music" : "Mute music",
                onTap: music.toggleMuted,
              ),
            ),
          ),
        Positioned.fromRect(
          rect: layout.wordmark,
          child: IgnorePointer(
            child: AnimatedOpacity(
              opacity: wordmark == null ? 0 : 1,
              duration: const Duration(milliseconds: 300),
              child: TweenAnimationBuilder<Color?>(
                tween: ColorTween(end: wordmark ?? RewindColors.white),
                duration: const Duration(milliseconds: 300),
                builder: (context, color, _) => RewindWordmark(
                  color: color ?? RewindColors.white,
                  width: RewindChromeLayout.wordmarkSize.width,
                ),
              ),
            ),
          ),
        ),
        Positioned(
          right: RewindChromeLayout.sideInset,
          bottom: layout.bottom,
          child: _PopButton(
            buttonKey: shareKey,
            glyph: RewindGlyph.share,
            label: "Share",
            onTap: onShare,
          ),
        ),
        Positioned(
          right: RewindChromeLayout.sideInset,
          bottom: layout.bottom + RewindChromeLayout.buttonSize + 12,
          child: ExcludeSemantics(
            excluding: onShareVideo == null,
            child: _PopButton(
              buttonKey: videoKey,
              glyph: RewindGlyph.video,
              label: "Share video",
              onTap: onShareVideo,
            ),
          ),
        ),
      ],
    );
  }
}

class _PopButton extends StatelessWidget {
  const _PopButton({
    required this.buttonKey,
    required this.glyph,
    required this.label,
    required this.onTap,
  });

  final GlobalKey buttonKey;
  final RewindGlyph glyph;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final onTap = this.onTap;
    return IgnorePointer(
      ignoring: onTap == null,
      child: AnimatedScale(
        scale: onTap == null ? 0.4 : 1,
        duration: onTap == null
            ? const Duration(milliseconds: 200)
            : RewindMotion.pop.duration,
        curve: onTap == null ? Curves.easeIn : RewindMotion.pop,
        child: AnimatedOpacity(
          opacity: onTap == null ? 0 : 1,
          duration: const Duration(milliseconds: 200),
          child: RewindRoundButton(
            key: buttonKey,
            glyph: glyph,
            label: label,
            onTap: onTap ?? () {},
          ),
        ),
      ),
    );
  }
}

class RewindProgressRail extends StatelessWidget {
  const RewindProgressRail({
    required this.index,
    required this.count,
    required this.color,
    super.key,
  });

  final int index;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: "Page ${index + 1} of $count",
      child: ExcludeSemantics(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < count; i++)
              AnimatedContainer(
                duration: const Duration(milliseconds: 500),
                curve: RewindMotion.railBounce,
                width: 4,
                height: i == index ? 18 : 4,
                margin: const EdgeInsets.only(bottom: 5),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: i == index ? 1 : 0.45),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
