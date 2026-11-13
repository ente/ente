import "dart:async";

import "package:flutter/foundation.dart";
import "package:flutter/widgets.dart";
import "package:photos/ui/viewer/file/file_viewer_filmstrip_event.dart";

typedef FileViewerFilmstripCurrentIndex = int Function();

typedef FileViewerFilmstripIdentityAt = Object? Function(int index);

typedef FileViewerFilmstripImmediatePageJump = bool Function(int index);

typedef FileViewerFilmstripWaitsForImageFrame = bool Function(Object identity);

typedef FileViewerFilmstripTimeoutScheduler =
    VoidCallback Function(Duration delay, VoidCallback callback);

// Runs [callback] after a guaranteed future frame's paint phase.
typedef FileViewerFilmstripPaintScheduler =
    void Function(VoidCallback callback);

// A user scroll session starts with the drag and remains active through any
// ballistic coast. During that session, [previewIndex] exposes the centered
// thumbnail when it differs from the committed page. On commit, the preview
// stays visible until the destination page has had a guaranteed future paint
// opportunity.
class FileViewerFilmstripCoordinator {
  final FileViewerFilmstripCurrentIndex _currentIndex;
  final FileViewerFilmstripIdentityAt _identityAt;
  final FileViewerFilmstripImmediatePageJump _jumpToPageImmediately;
  final VoidCallback _requestPauseCurrentMedia;
  final FileViewerFilmstripPaintScheduler _scheduleAfterNextFramePaint;
  final FileViewerFilmstripWaitsForImageFrame _waitsForImageFrame;
  final FileViewerFilmstripTimeoutScheduler _scheduleTimeout;

  final ValueNotifier<int?> _previewIndexNotifier = ValueNotifier(null);
  final Map<Object, _ActiveImagePage> _activeImagePages = Map.identity();

  _FilmstripSession _session = const _IdleFilmstripSession();
  Object? _imageFrameWaitTimeoutToken;
  VoidCallback? _cancelImageFrameWaitTimeout;
  bool _isDisposed = false;

  FileViewerFilmstripCoordinator({
    required FileViewerFilmstripCurrentIndex currentIndex,
    required FileViewerFilmstripIdentityAt identityAt,
    required FileViewerFilmstripImmediatePageJump jumpToPageImmediately,
    required VoidCallback requestPauseCurrentMedia,
    FileViewerFilmstripWaitsForImageFrame? waitsForImageFrame,
    FileViewerFilmstripPaintScheduler? scheduleAfterNextFramePaint,
    FileViewerFilmstripTimeoutScheduler? scheduleTimeout,
  }) : _currentIndex = currentIndex,
       _identityAt = identityAt,
       _jumpToPageImmediately = jumpToPageImmediately,
       _requestPauseCurrentMedia = requestPauseCurrentMedia,
       _waitsForImageFrame = waitsForImageFrame ?? ((_) => false),
       _scheduleTimeout = scheduleTimeout ?? _afterTimeout,
       _scheduleAfterNextFramePaint =
           scheduleAfterNextFramePaint ?? _afterNextFramePaint;

  ValueListenable<int?> get previewIndex => _previewIndexNotifier;

  bool get isUserScrollSessionActive => _session is _ScrubbingFilmstripSession;

  void handleEvent(FileViewerFilmstripEvent event) {
    if (_isDisposed) return;
    final (:index, :type) = event;

    switch (type) {
      case FileViewerFilmstripEventType.tap:
        reset();
        if (_identityAt(index) == null) return;
        if (index != _currentIndex()) {
          _jumpToPageImmediately(index);
        }
        return;
      case FileViewerFilmstripEventType.scrubStart:
        _setSession(const _ScrubbingFilmstripSession());
        return;
      case FileViewerFilmstripEventType.scrubPreview:
        if (_identityAt(index) == null) return;
        final session = _session is _ScrubbingFilmstripSession
            ? _session as _ScrubbingFilmstripSession
            : const _ScrubbingFilmstripSession();
        final previewIndex = index == _currentIndex() ? null : index;
        final shouldRequestPause =
            previewIndex != null && !session.didRequestPause;
        final nextSession = _ScrubbingFilmstripSession(
          previewIndex: previewIndex,
          didRequestPause: session.didRequestPause || shouldRequestPause,
        );
        _setSession(nextSession);
        if (shouldRequestPause && identical(_session, nextSession)) {
          _requestPauseCurrentMedia();
        }
        return;
      case FileViewerFilmstripEventType.scrubCommit:
        final targetIdentity = _identityAt(index);
        if (targetIdentity == null) {
          reset();
          return;
        }
        _commit(index, targetIdentity);
        return;
    }
  }

  void handlePageChanged(int index, Object fileIdentity) {
    if (_isDisposed) return;
    final pendingSession = _session;
    if (pendingSession is! _PendingFilmstripHandoffSession ||
        pendingSession.previewRemovalScheduled ||
        !_matchesPendingHandoff(pendingSession, index, fileIdentity)) {
      return;
    }
    final session = pendingSession.copyWith(destinationPageSelected: true);
    _setSession(session);
    _schedulePreviewRemovalIfReady(session);
  }

  void attachImagePage(Object fileIdentity, ValueListenable<bool> readiness) {
    if (_isDisposed) return;
    final currentPage = _activeImagePages[fileIdentity];
    if (currentPage != null) {
      if (identical(currentPage.readiness, readiness)) return;
      currentPage.readiness.removeListener(currentPage.listener);
    }

    void listener() =>
        _handleImagePageReadinessChanged(fileIdentity, readiness);

    _activeImagePages[fileIdentity] = (
      readiness: readiness,
      listener: listener,
    );
    readiness.addListener(listener);
    _handleImagePageReadinessChanged(fileIdentity, readiness);
  }

  void detachImagePage(Object fileIdentity, ValueListenable<bool> readiness) {
    if (_isDisposed) return;
    final currentPage = _activeImagePages[fileIdentity];
    if (currentPage == null || !identical(currentPage.readiness, readiness)) {
      return;
    }
    readiness.removeListener(currentPage.listener);
    _activeImagePages.remove(fileIdentity);
    _invalidateScheduledRemovalFor(fileIdentity);
    final session = _session;
    if (session is _PendingFilmstripHandoffSession &&
        identical(session.identity, fileIdentity)) {
      _schedulePreviewRemovalIfReady(session);
    }
  }

  void _handleImagePageReadinessChanged(
    Object fileIdentity,
    ValueListenable<bool> readiness,
  ) {
    final currentPage = _activeImagePages[fileIdentity];
    if (currentPage == null || !identical(currentPage.readiness, readiness)) {
      return;
    }
    if (!readiness.value) {
      _invalidateScheduledRemovalFor(fileIdentity);
      final session = _session;
      if (session is _PendingFilmstripHandoffSession &&
          identical(session.identity, fileIdentity)) {
        _schedulePreviewRemovalIfReady(session);
      }
      return;
    }
    final session = _session;
    if (session is _PendingFilmstripHandoffSession &&
        identical(session.identity, fileIdentity)) {
      _schedulePreviewRemovalIfReady(session);
    }
  }

  void _invalidateScheduledRemovalFor(Object fileIdentity) {
    final session = _session;
    if (session is! _PendingFilmstripHandoffSession ||
        !session.previewRemovalScheduled ||
        !identical(session.identity, fileIdentity)) {
      return;
    }
    _setSession(session.copyWith(previewRemovalScheduled: false));
  }

  void _schedulePreviewRemovalIfReady(
    _PendingFilmstripHandoffSession pendingSession,
  ) {
    if (pendingSession.previewRemovalScheduled ||
        !pendingSession.destinationPageSelected) {
      return;
    }
    if (_waitsForImageFrame(pendingSession.identity)) {
      final imagePage = _activeImagePages[pendingSession.identity];
      if (imagePage == null || !imagePage.readiness.value) {
        _scheduleImageFrameWaitTimeout(pendingSession);
        return;
      }
    }
    _schedulePreviewRemoval(pendingSession);
  }

  void _scheduleImageFrameWaitTimeout(
    _PendingFilmstripHandoffSession pendingSession,
  ) {
    if (_cancelImageFrameWaitTimeout != null) return;
    final token = Object();
    _imageFrameWaitTimeoutToken = token;
    _cancelImageFrameWaitTimeout = _scheduleTimeout(
      const Duration(seconds: 5),
      () {
        if (_isDisposed || !identical(_imageFrameWaitTimeoutToken, token)) {
          return;
        }
        _imageFrameWaitTimeoutToken = null;
        _cancelImageFrameWaitTimeout = null;
        final session = _session;
        if (session is _PendingFilmstripHandoffSession &&
            session.destinationPageSelected &&
            !session.previewRemovalScheduled &&
            _matchesPendingHandoff(
              session,
              pendingSession.index,
              pendingSession.identity,
            )) {
          _schedulePreviewRemoval(session);
        }
      },
    );
  }

  void _schedulePreviewRemoval(_PendingFilmstripHandoffSession pendingSession) {
    _cancelPendingImageFrameWaitTimeout();
    final session = pendingSession.copyWith(previewRemovalScheduled: true);
    _setSession(session);
    _scheduleAfterNextFramePaint(() {
      if (_isDisposed ||
          !identical(_session, session) ||
          _currentIndex() != session.index ||
          !identical(_identityAt(session.index), session.identity)) {
        return;
      }
      reset();
    });
  }

  void reset() {
    if (_isDisposed) return;
    _setSession(const _IdleFilmstripSession());
  }

  void _commit(int index, Object targetIdentity) {
    if (index == _currentIndex()) {
      final session = _session;
      if (session is! _PendingFilmstripHandoffSession ||
          !_matchesPendingHandoff(session, index, targetIdentity)) {
        reset();
      }
      return;
    }

    final session = _PendingFilmstripHandoffSession(index, targetIdentity);
    _setSession(session);
    if (!identical(_session, session)) return;
    if (!_jumpToPageImmediately(index)) {
      reset();
    }
  }

  bool _matchesPendingHandoff(
    _PendingFilmstripHandoffSession session,
    int index,
    Object identity,
  ) => session.index == index && identical(session.identity, identity);

  void _setSession(_FilmstripSession session) {
    if (!_hasSamePendingTarget(_session, session)) {
      _cancelPendingImageFrameWaitTimeout();
    }
    _session = session;
    _previewIndexNotifier.value = session.previewIndex;
  }

  void dispose() {
    _isDisposed = true;
    _cancelPendingImageFrameWaitTimeout();
    _session = const _IdleFilmstripSession();
    for (final page in _activeImagePages.values) {
      page.readiness.removeListener(page.listener);
    }
    _activeImagePages.clear();
    _previewIndexNotifier.dispose();
  }

  bool _hasSamePendingTarget(_FilmstripSession a, _FilmstripSession b) =>
      a is _PendingFilmstripHandoffSession &&
      b is _PendingFilmstripHandoffSession &&
      a.index == b.index &&
      identical(a.identity, b.identity);

  void _cancelPendingImageFrameWaitTimeout() {
    _imageFrameWaitTimeoutToken = null;
    _cancelImageFrameWaitTimeout?.call();
    _cancelImageFrameWaitTimeout = null;
  }
}

sealed class _FilmstripSession {
  const _FilmstripSession();

  int? get previewIndex;
}

final class _IdleFilmstripSession extends _FilmstripSession {
  const _IdleFilmstripSession();

  @override
  int? get previewIndex => null;
}

final class _ScrubbingFilmstripSession extends _FilmstripSession {
  @override
  final int? previewIndex;
  final bool didRequestPause;

  const _ScrubbingFilmstripSession({
    this.previewIndex,
    this.didRequestPause = false,
  });
}

final class _PendingFilmstripHandoffSession extends _FilmstripSession {
  final int index;
  final Object identity;
  final bool destinationPageSelected;
  final bool previewRemovalScheduled;

  @override
  int get previewIndex => index;

  const _PendingFilmstripHandoffSession(
    this.index,
    this.identity, {
    this.destinationPageSelected = false,
    this.previewRemovalScheduled = false,
  });

  _PendingFilmstripHandoffSession copyWith({
    bool? destinationPageSelected,
    bool? previewRemovalScheduled,
  }) => _PendingFilmstripHandoffSession(
    index,
    identity,
    destinationPageSelected:
        destinationPageSelected ?? this.destinationPageSelected,
    previewRemovalScheduled:
        previewRemovalScheduled ?? this.previewRemovalScheduled,
  );
}

typedef _ActiveImagePage = ({
  ValueListenable<bool> readiness,
  VoidCallback listener,
});

void _afterNextFramePaint(VoidCallback callback) {
  WidgetsBinding.instance.scheduleFrameCallback((_) {
    WidgetsBinding.instance.addPostFrameCallback((_) => callback());
  });
}

VoidCallback _afterTimeout(Duration delay, VoidCallback callback) {
  final timer = Timer(delay, callback);
  return timer.cancel;
}
