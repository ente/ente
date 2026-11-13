import "dart:math";

import "package:flutter/material.dart";
import "package:photos/ui/rewind/shell/rewind_page.dart";
import "package:photos/ui/rewind/shell/rewind_viewer.dart";
import "package:photos/ui/rewind/story/rewind_story.dart";

class RewindStoryView extends StatefulWidget {
  const RewindStoryView({
    required this.story,
    this.initialPage,
    this.initialStop = 0,
    this.onSettled,
    super.key,
  });

  final RewindStory story;
  final String? initialPage;
  final int initialStop;
  final void Function(RewindPage page, int stop)? onSettled;

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
  late final _initialPage = widget.story.resumeAt(widget.initialPage);

  @override
  void initState() {
    super.initState();
    for (final page in widget.story.pages) {
      page.resetAnswer();
    }
    widget.story.preloadFrom(widget.story.indexOf(_initialPage));
  }

  @override
  Widget build(BuildContext context) {
    final story = widget.story;
    return RewindViewer(
      pages: story.pages,
      initialPage: _initialPage,
      initialStop: _initialPage == widget.initialPage ? widget.initialStop : 0,
      onSettled: (page, stop) {
        story.preloadFrom(max(0, story.pages.indexOf(page)));
        widget.onSettled?.call(page, stop);
      },
    );
  }
}
