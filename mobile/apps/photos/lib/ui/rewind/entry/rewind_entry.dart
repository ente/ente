import "dart:async";

import "package:flutter/material.dart";
import "package:photos/service_locator.dart";
import "package:photos/services/app_navigation_service.dart";
import "package:photos/ui/rewind/story/rewind_story.dart";
import "package:photos/ui/rewind/story/rewind_story_view.dart";

class RewindEntry {
  const RewindEntry._(this._story);

  static RewindEntry? current() {
    final story = rewindService.story.value;
    return story == null ? null : RewindEntry._(story);
  }

  static Future<void> openWhenReady(BuildContext context) async {
    await rewindService.refresh();
    if (!context.mounted || AppNavigationService.instance.isGuestViewActive) {
      return;
    }
    await current()?.open(context);
  }

  final RewindStory _story;

  bool get opened => rewindService.progress.opened;

  bool get completed => rewindService.progress.completed;

  bool get started => opened && !completed;

  int get resumeIndex => _story.resumeIndex(rewindService.progress.resumePage);

  int get pageCount => _story.pages.length;

  Future<void> open(BuildContext context) {
    final progress = rewindService.progress;
    final resume = !progress.completed;
    unawaited(rewindService.markOpened());
    return Navigator.of(context).push(
      RewindStoryView(
        story: _story,
        initialPage: resume ? progress.resumePage : null,
        initialStop: resume ? progress.resumeStop : 0,
        onSettled: (page, stop) {
          unawaited(progress.saveResume(page.key, stop));
          if (identical(page, _story.pages.last)) {
            unawaited(progress.markCompleted());
          }
        },
      ).route(),
    );
  }
}
