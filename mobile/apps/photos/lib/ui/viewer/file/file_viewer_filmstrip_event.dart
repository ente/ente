import "package:flutter/foundation.dart";

enum FileViewerFilmstripEventType { tap, scrubStart, scrubPreview, scrubCommit }

// Scrub start and commit are lifecycle events, so they are emitted even when
// [index] has not changed. Preview and tap events identify a newly focused
// item.
typedef FileViewerFilmstripEvent = ({
  int index,
  FileViewerFilmstripEventType type,
});

typedef FileViewerFilmstripEventCallback =
    ValueChanged<FileViewerFilmstripEvent>;
