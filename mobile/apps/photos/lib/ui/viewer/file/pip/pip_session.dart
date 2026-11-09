import "dart:async";

import "package:ente_lock_screen/lock_screen_settings.dart";
import "package:ente_pip/ente_pip.dart";
import "package:flutter/widgets.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/events/pause_video_event.dart";
import "package:photos/events/user_logged_out_event.dart";
import "package:photos/models/file/file.dart";
import "package:photos/services/app_navigation_service.dart";
import "package:photos/services/collections_service.dart";
import "package:photos/ui/viewer/file/detail_page.dart";

// Tracks the video playing in Picture-in-Picture for "back to video".
//
// A viewer showing the video continues it. Otherwise a viewer is opened for
// it, except in Guest view, for hidden videos, and when Ente may be locked.
class PipSession {
  PipSession._();

  static EnteFile? _file;
  static String? _path;
  static ({String tag, Duration position})? _resume;
  static bool _isListening = false;

  static void started(EnteFile file, String path) {
    _file = file;
    _path = path;
    if (_isListening) return;
    _isListening = true;
    EntePip.fallbackRestoreHandler = _openViewer;
    Bus.instance.on<UserLoggedOutEvent>().listen((_) {
      _file = null;
      _path = null;
      _resume = null;
      EntePip.stop().ignore();
    });
  }

  // Returning from the background with app lock on shows the lock screen, so
  // playback must not continue above it.
  static bool get mayBeLocked =>
      LockScreenSettings.instance.getIsAppLockSet() &&
      WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed;

  // Taken once, when the viewer opened by "back to video" is created, so a
  // later viewer of the same video starts normally.
  static Duration? takeResumePosition(EnteFile file) {
    final resume = _resume;
    if (resume == null || resume.tag != file.tag) return null;
    _resume = null;
    return resume.position;
  }

  // Continues "back to video" in a viewer that shows the PiP video. While Ente
  // may be locked, the viewer only moves to PiP's position and stays paused.
  static bool handOver(
    BuildContext context, {
    required bool isShowingVideo,
    required Future<void> Function() seek,
    required Future<void> Function() play,
  }) {
    if (!isShowingVideo || !(ModalRoute.of(context)?.isCurrent ?? false)) {
      return false;
    }
    if (mayBeLocked) {
      unawaited(seek());
      return false;
    }
    unawaited(() async {
      try {
        await seek();
        await play();
      } finally {
        await EntePip.finishRestore();
      }
    }());
    return true;
  }

  static bool _openViewer(PipRestore restore) {
    final file = _file;
    final navigation = AppNavigationService.instance;
    if (file == null ||
        restore.path != _path ||
        navigation.isGuestViewActive ||
        mayBeLocked ||
        _isHidden(file)) {
      return false;
    }
    _resume = (tag: file.tag, position: restore.position);
    Bus.instance.fire(PauseVideoEvent());
    unawaited(
      navigation.pushPage(
        DetailPage(DetailPageConfiguration([file], 0, "pip_restore")),
      ),
    );
    return true;
  }

  static bool _isHidden(EnteFile file) {
    final collectionID = file.collectionID;
    return collectionID != null &&
        CollectionsService.instance.getHiddenCollectionIds().contains(
          collectionID,
        );
  }
}
