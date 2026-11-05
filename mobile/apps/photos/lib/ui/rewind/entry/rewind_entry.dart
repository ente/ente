import "dart:async";
import "dart:math";

import "package:flutter/material.dart";
import "package:photos/service_locator.dart";
import "package:photos/services/app_navigation_service.dart";
import "package:photos/src/rust/api/rewind_api.dart" as rust;
import "package:photos/ui/rewind/shell/rewind_page.dart";
import "package:photos/ui/rewind/shell/rewind_viewer.dart";
import "package:photos/ui/rewind/story/rewind_composer.dart";

class RewindEntry {
  const RewindEntry._(this.pages);

  static RewindEntry? current() {
    final status = rewindService.state.value?.status;
    if (status is! rust.RewindStatus_Ready) return null;
    return RewindEntry._(composeRewind(status.report));
  }

  static Future<void> openWhenReady(BuildContext context) async {
    await rewindService.refresh();
    if (!context.mounted || AppNavigationService.instance.isGuestViewActive) {
      return;
    }
    await current()?.open(context);
  }

  final List<RewindPage> pages;

  bool get opened => rewindService.progress.opened;

  bool get completed => rewindService.progress.completed;

  bool get started => opened && !completed;

  int get resumeIndex {
    final resumePage = rewindService.progress.resumePage;
    return max(0, pages.indexWhere((page) => page.key == resumePage));
  }

  Future<void> open(BuildContext context) {
    final progress = rewindService.progress;
    final resume = !progress.completed;
    unawaited(rewindService.markOpened());
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RewindViewer(
          pages: pages,
          initialPage: resume ? progress.resumePage : null,
          initialStop: resume ? progress.resumeStop : 0,
          onSettled: (page, stop) {
            unawaited(progress.saveResume(page.key, stop));
            if (identical(page, pages.last)) {
              unawaited(progress.markCompleted());
            }
          },
        ),
      ),
    );
  }
}
