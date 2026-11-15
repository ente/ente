import "package:flutter/foundation.dart";
import "package:flutter/widgets.dart";
import "package:photos/ui/rewind/shell/rewind_chrome.dart";
import "package:photos/ui/rewind/shell/rewind_page.dart";
import "package:photos/ui/rewind/shell/rewind_page_scope.dart";
import "package:photos/ui/rewind/shell/rewind_page_stack.dart";
import "package:photos/ui/rewind/theme/rewind_colors.dart";
import "package:photos/ui/rewind/theme/rewind_motion.dart";
import "package:photos/ui/rewind/widgets/rewind_wordmark.dart";

class RewindReel {
  RewindReel._(this.pages, this._holds)
    : starts = RewindPageStack.startsOf(pages);

  factory RewindReel.of(List<RewindPage> story) {
    final pages = <RewindPage>[];
    final holds = <Duration>[];
    for (final page in story) {
      final hold = page.reelHold;
      if (hold == null) continue;
      pages.add(page);
      holds.addAll(List.filled(page.stops, hold));
    }
    return RewindReel._(pages, holds);
  }

  static const frameRate = 30;
  static const canvas = Size(360, 640);
  static const _turn = RewindMotion.waveDuration;

  final List<RewindPage> pages;
  final List<int> starts;
  final List<Duration> _holds;

  Duration get duration =>
      _holds.fold(Duration.zero, (total, hold) => total + hold) +
      _turn * (_holds.length - 1);

  int get frameCount =>
      (duration.inMicroseconds * frameRate / Duration.microsecondsPerSecond)
          .ceil();

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

class RewindReelView extends StatelessWidget {
  const RewindReelView({
    required this.reel,
    required this.time,
    required this.pixelRatio,
    super.key,
  });

  final RewindReel reel;
  final ValueListenable<Duration> time;
  final double pixelRatio;

  static const _navigator = _ReelNavigator();

  @override
  Widget build(BuildContext context) {
    final layout = RewindChromeLayout(RewindReel.canvas, EdgeInsets.zero);
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(
        size: RewindReel.canvas,
        devicePixelRatio: pixelRatio,
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
              valueListenable: time,
              builder: (context, time, _) {
                final scroll = reel.scrollAt(time);
                final wordmark = reel.pageAt(scroll).chrome.wordmark;
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    RewindPageStack(
                      pages: reel.pages,
                      starts: reel.starts,
                      scroll: scroll,
                      navigator: _navigator,
                      reel: true,
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
}
