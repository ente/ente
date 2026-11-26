import "dart:math";

import "package:flutter/foundation.dart";
import "package:flutter/widgets.dart";
import "package:photos/ui/rewind/reel/rewind_end_card.dart";
import "package:photos/ui/rewind/shell/rewind_chrome.dart";
import "package:photos/ui/rewind/shell/rewind_page.dart";
import "package:photos/ui/rewind/shell/rewind_page_scope.dart";
import "package:photos/ui/rewind/shell/rewind_page_stack.dart";
import "package:photos/ui/rewind/theme/rewind_colors.dart";
import "package:photos/ui/rewind/theme/rewind_motion.dart";
import "package:photos/ui/rewind/widgets/rewind_wordmark.dart";

class RewindReel {
  RewindReel._(this.pages, this._holds, {required this.clip})
    : starts = RewindPageStack.startsOf(pages);

  factory RewindReel.of(List<RewindPage> story) =>
      RewindReel._holding(story, (page) => page.reelHold, clip: false);

  factory RewindReel.clipOf(List<RewindPage> pages) =>
      RewindReel._holding(pages, (page) => page.clipHold, clip: true);

  factory RewindReel._holding(
    List<RewindPage> story,
    Duration? Function(RewindPage page) holdOf, {
    required bool clip,
  }) {
    final pages = <RewindPage>[];
    final holds = <Duration>[];
    for (final page in story) {
      final hold = holdOf(page);
      if (hold == null) continue;
      pages.add(page);
      holds.addAll(List.filled(page.stops, hold));
    }
    return RewindReel._(pages, holds, clip: clip);
  }

  static const frameRate = 24;
  static const canvas = Size(360, 640);
  static const _turn = RewindMotion.waveDuration;

  final List<RewindPage> pages;
  final List<int> starts;
  final bool clip;
  final List<Duration> _holds;

  Duration get storyEnd =>
      _holds.fold(Duration.zero, (total, hold) => total + hold) +
      _turn * (_holds.length - 1);

  Duration get duration => storyEnd + RewindEndCard.duration;

  Duration get videoDuration => duration + timeOf(1);

  int get frameCount =>
      (duration.inMicroseconds * frameRate / Duration.microsecondsPerSecond)
          .ceil();

  int get coverFrame => _frameAt(clip ? storyEnd : _holds.first);

  int get storyEndFrame => _frameAt(storyEnd);

  int _frameAt(Duration time) => min(
    frameCount - 1,
    time.inMicroseconds * frameRate ~/ Duration.microsecondsPerSecond,
  );

  Duration timeOf(int frame) => Duration(
    microseconds: (frame * Duration.microsecondsPerSecond / frameRate).round(),
  );

  double scrollAt(Duration time) {
    var left = time;
    for (var step = 0; step < _holds.length - 1; step++) {
      if (left <= _holds[step]) return step.toDouble();
      left -= _holds[step];
      if (left < _turn) {
        return step +
            RewindMotion.wave.transform(
              left.inMicroseconds / _turn.inMicroseconds,
            );
      }
      left -= _turn;
    }
    return _holds.length - 1;
  }

  RewindPage pageAt(double scroll) =>
      pages[starts.lastIndexWhere((start) => start <= scroll.round())];
}

class RewindReelView extends StatefulWidget {
  const RewindReelView({
    required this.reel,
    required this.time,
    required this.pixelRatio,
    super.key,
  });

  final RewindReel reel;
  final ValueListenable<Duration> time;
  final double pixelRatio;

  @override
  State<RewindReelView> createState() => _RewindReelViewState();
}

class _RewindReelViewState extends State<RewindReelView> {
  static const _navigator = _ReelNavigator();
  static const _beforeEndCard = Duration(microseconds: -1);

  late final _scroll = ValueNotifier(_scrollNow);
  late final _ending = ValueNotifier(_endingNow);

  double get _scrollNow => widget.reel.scrollAt(widget.time.value);

  Duration get _endingNow {
    final ending = widget.time.value - widget.reel.storyEnd;
    return ending.isNegative ? _beforeEndCard : ending;
  }

  @override
  void initState() {
    super.initState();
    widget.time.addListener(_update);
  }

  @override
  void didUpdateWidget(RewindReelView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.time != widget.time) {
      oldWidget.time.removeListener(_update);
      widget.time.addListener(_update);
    }
    _update();
  }

  @override
  void dispose() {
    widget.time.removeListener(_update);
    _scroll.dispose();
    _ending.dispose();
    super.dispose();
  }

  void _update() {
    _scroll.value = _scrollNow;
    _ending.value = _endingNow;
  }

  @override
  Widget build(BuildContext context) {
    final reel = widget.reel;
    final layout = RewindChromeLayout(RewindReel.canvas, EdgeInsets.zero);
    final story = ValueListenableBuilder(
      valueListenable: _scroll,
      builder: (context, scroll, _) {
        final wordmark =
            reel.pageAt(scroll).chrome.wordmark ??
            (reel.clip ? RewindColors.white : null);
        return Stack(
          fit: StackFit.expand,
          children: [
            RewindPageStack(
              pages: reel.pages,
              starts: reel.starts,
              scroll: scroll,
              navigator: _navigator,
              reel: true,
              clip: reel.clip,
            ),
            if (wordmark != null)
              Positioned.fromRect(
                rect: layout.wordmark,
                child: TweenAnimationBuilder<Color?>(
                  tween: ColorTween(end: wordmark),
                  duration: const Duration(milliseconds: 300),
                  builder: (context, color, _) => RewindWordmark(
                    color: color ?? wordmark,
                    width: RewindChromeLayout.wordmarkSize.width,
                  ),
                ),
              ),
          ],
        );
      },
    );
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(
        size: RewindReel.canvas,
        devicePixelRatio: widget.pixelRatio,
        padding: EdgeInsets.zero,
        viewPadding: EdgeInsets.zero,
        viewInsets: EdgeInsets.zero,
        textScaler: TextScaler.noScaling,
      ),
      child: ExcludeSemantics(
        child: IgnorePointer(
          child: ColoredBox(
            color: RewindColors.ink,
            child: ValueListenableBuilder(
              valueListenable: _ending,
              child: story,
              builder: (context, ending, story) => Stack(
                fit: StackFit.expand,
                children: [
                  Offstage(
                    offstage: ending.isNegative,
                    child: RewindEndCard(elapsed: ending),
                  ),
                  RewindCardExit(elapsed: ending, child: story!),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ReelNavigator implements RewindNavigator {
  const _ReelNavigator();

  @override
  void next() {}

  @override
  void previous() {}

  @override
  void attachShareCard(RewindPage page, RewindShareCard card) {}

  @override
  void detachShareCard(RewindPage page, RewindShareCard card) {}

  @override
  void shareVideo(Rect? origin) {}

  @override
  ValueListenable<bool> get videoSaved => const AlwaysStoppedAnimation(false);

  @override
  void saveVideo() {}
}
