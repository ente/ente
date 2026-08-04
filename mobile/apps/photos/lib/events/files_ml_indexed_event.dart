import "package:photos/events/event.dart";

/// Fired when files have finished ML indexing (locally, via remote
/// hydration, or by storing a skip marker for an unprocessable file).
class FilesMLIndexedEvent extends Event {
  /// uploadedFileIDs in online mode, local int IDs in local gallery mode.
  final List<int> fileKeys;
  final bool isLocalGallery;

  FilesMLIndexedEvent(this.fileKeys, {required this.isLocalGallery});
}
