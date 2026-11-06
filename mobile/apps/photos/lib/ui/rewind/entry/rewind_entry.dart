import "dart:async";
import "dart:math";

import "package:flutter/material.dart";
import "package:photos/service_locator.dart";
import "package:photos/services/app_navigation_service.dart";
import "package:photos/src/rust/api/rewind_api.dart" as rust;
import "package:photos/ui/rewind/story/rewind_composer.dart";
import "package:photos/ui/rewind/story/rewind_story.dart";
import "package:photos/ui/rewind/story/rewind_story_view.dart";

class RewindEntry {
  const RewindEntry._(this._report, this.pages);

  static RewindEntry? current() {
    final status = rewindService.state.value?.status;
    if (status is! rust.RewindStatus_Ready) return null;
    return RewindEntry._(status.report, rewindOutline(status.report));
  }

  static Future<void> openWhenReady(BuildContext context) async {
    await rewindService.refresh();
    if (!context.mounted || AppNavigationService.instance.isGuestViewActive) {
      return;
    }
    await current()?.open(context);
  }

  final rust.RewindReport _report;
  final List<String> pages;

  bool get opened => rewindService.progress.opened;

  bool get completed => rewindService.progress.completed;

  bool get started => opened && !completed;

  int get resumeIndex =>
      max(0, pages.indexOf(rewindService.progress.resumePage ?? ""));

  Future<void> open(BuildContext context) {
    final progress = rewindService.progress;
    final resume = !progress.completed;
    unawaited(rewindService.markOpened());
    return Navigator.of(context).push(
      RewindStoryView(
        story: RewindStory.prepare(_report),
        initialPage: resume ? progress.resumePage : null,
        initialStop: resume ? progress.resumeStop : 0,
        onSettled: (story, page, stop) {
          unawaited(progress.saveResume(page.key, stop));
          if (identical(page, story.pages.last)) {
            unawaited(progress.markCompleted());
          }
        },
      ).route(),
    );
  }
}
