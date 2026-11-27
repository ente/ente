import "dart:io";

import "package:photos/models/file/file.dart";
import "package:photos/service_locator.dart";
import "package:photos/utils/hls_playlist.dart";

class PipStream {
  PipStream._();

  static const _maxPreparedAge = Duration(minutes: 5);
  static ({String tag, DateTime createdAt, Future<String> playlist})? _prepared;

  static void prepare(EnteFile file, File localPlaylist) {
    if (_preparedFor(file) != null) return;
    final playlist = _build(file, localPlaylist);
    _prepared = (tag: file.tag, createdAt: DateTime.now(), playlist: playlist);
    playlist
        .then<void>(
          (_) {},
          onError: (Object _) {
            if (identical(_prepared?.playlist, playlist)) _prepared = null;
          },
        )
        .ignore();
  }

  static Future<String> playlistFor(EnteFile file, File localPlaylist) {
    final prepared = _preparedFor(file);
    _prepared = null;
    return prepared ?? _build(file, localPlaylist);
  }

  static Future<String>? _preparedFor(EnteFile file) {
    final prepared = _prepared;
    if (prepared == null ||
        prepared.tag != file.tag ||
        DateTime.now().difference(prepared.createdAt) > _maxPreparedAge) {
      return null;
    }
    return prepared.playlist;
  }

  static Future<String> _build(EnteFile file, File localPlaylist) async {
    final playlist = await localPlaylist.readAsString();
    // AVPlayer needs HTTPS segments even when the preview is cached.
    final segmentUrl = await _previewUrl(file);
    return reconstructHlsPlaylist(playlist, segmentUrl);
  }

  static Future<String> _previewUrl(EnteFile file) {
    final fileID = file.uploadedFileID!;
    final collectionID = file.collectionID!;
    if (collectionsService.isSharedPublicLink(collectionID)) {
      return fileDataGateway.getPublicPreview(
        baseUrl: endpointConfig.endpoint,
        fileID: fileID,
        type: "vid_preview",
        headers: collectionsService.publicCollectionHeaders(collectionID),
        nonEnteDio: ServiceLocator.instance.nonEnteDio,
      );
    }
    return fileDataGateway.getPreview(fileID: fileID, type: "vid_preview");
  }
}
