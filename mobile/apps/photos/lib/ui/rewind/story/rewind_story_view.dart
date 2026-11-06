import "dart:math";

import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:logging/logging.dart";
import "package:photos/ui/rewind/shell/rewind_page.dart";
import "package:photos/ui/rewind/shell/rewind_viewer.dart";
import "package:photos/ui/rewind/story/rewind_story.dart";
import "package:photos/ui/rewind/theme/rewind_colors.dart";
import "package:photos/ui/rewind/widgets/rewind_backdrop.dart";
import "package:photos/ui/rewind/widgets/rewind_buttons.dart";
import "package:photos/ui/rewind/widgets/rewind_entrance.dart";
import "package:photos/ui/rewind/widgets/rewind_stickers.dart";

class RewindStoryView extends StatefulWidget {
  const RewindStoryView({
    required this.story,
    this.initialPage,
    this.initialStop = 0,
    this.onSettled,
    super.key,
  });

  final Future<RewindStory> story;
  final String? initialPage;
  final int initialStop;
  final void Function(RewindStory story, RewindPage page, int stop)? onSettled;

  Route<void> route() => PageRouteBuilder<void>(
    transitionDuration: const Duration(milliseconds: 260),
    reverseTransitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (_, _, _) => this,
    transitionsBuilder: (_, animation, _, child) => FadeTransition(
      opacity: CurvedAnimation(
        parent: animation,
        curve: Curves.easeOut,
        reverseCurve: Curves.easeIn,
      ),
      child: child,
    ),
  );

  @override
  State<RewindStoryView> createState() => _RewindStoryViewState();
}

class _RewindStoryViewState extends State<RewindStoryView> {
  static final _logger = Logger("RewindStoryView");

  RewindStory? _story;

  @override
  void initState() {
    super.initState();
    widget.story.then(_show, onError: _fail);
  }

  void _show(RewindStory story) {
    if (!mounted) return;
    story.preloadFrom(story.indexOf(widget.initialPage));
    setState(() => _story = story);
  }

  void _fail(Object error, StackTrace stackTrace) {
    _logger.severe("Could not prepare the Rewind story", error, stackTrace);
    if (mounted) Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final story = _story;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: story == null
          ? const _Preparing()
          : RewindViewer(
              key: ObjectKey(story),
              pages: story.pages,
              initialPage: widget.initialPage,
              initialStop: widget.initialStop,
              onSettled: (page, stop) {
                story.preloadFrom(max(0, story.pages.indexOf(page)));
                widget.onSettled?.call(story, page, stop);
              },
            ),
    );
  }
}

class _Preparing extends StatelessWidget {
  const _Preparing();

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: RewindColors.green,
        body: Stack(
          fit: StackFit.expand,
          children: [
            const RewindBackdrop(
              color: RewindColors.green,
              doodle: RewindColors.doodleGreen,
              grain: 0,
            ),
            Center(
              child: RewindEntrance(
                preset: RewindPreset.pop,
                active: true,
                delayMs: 350,
                child: RewindIdleLoop(
                  idle: RewindIdle.pulse,
                  active: true,
                  delayMs: 1100,
                  child: Transform.rotate(
                    angle: -4 * pi / 180,
                    child: const RewindLabelSticker("REWINDING…", size: 24),
                  ),
                ),
              ),
            ),
            Positioned(
              top: MediaQuery.paddingOf(context).top + 5,
              right: 22,
              child: RewindRoundButton(
                glyph: RewindGlyph.close,
                label: "Close",
                size: 36,
                ring: false,
                onTap: () => Navigator.of(context).maybePop(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
