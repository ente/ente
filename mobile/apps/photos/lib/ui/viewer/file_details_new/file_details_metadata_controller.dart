import "dart:io";

import "package:exif_reader/exif_reader.dart";
import "package:flutter/foundation.dart";
import "package:logging/logging.dart";
import "package:photos/models/ffmpeg/ffprobe_props.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/location/location.dart";
import "package:photos/models/metadata/file_magic.dart";
import "package:photos/module/download/file.dart";
import "package:photos/module/metadata/exif.dart";
import "package:photos/module/metadata/video.dart";
import "package:photos/services/file_magic_service.dart";
import "package:photos/ui/viewer/file_details_new/file_details_exif.dart";

class FileDetailsMetadataController {
  FileDetailsMetadataController({
    required this.file,
    required this.currentUserID,
  }) : hasLocation = ValueNotifier(file.hasLocation);

  final EnteFile file;
  final int currentUserID;
  final ValueNotifier<Map<String, IfdTag>?> exifTags = ValueNotifier(null);
  final ValueNotifier<FileDetailsExif?> exifDetails = ValueNotifier(null);
  final ValueNotifier<FFProbeProps?> videoMetadata = ValueNotifier(null);
  final ValueNotifier<bool> hasLocation;
  final Logger _logger = Logger("FileDetailsMetadataController");

  Future<void>? _exifLoad;
  Future<void>? _videoLoad;
  bool _disposed = false;

  Future<void> loadExif() => _exifLoad ??= _loadExif();

  Future<void> loadVideo() => _videoLoad ??= _loadVideo();

  Future<void> _loadExif() async {
    Map<String, IfdTag> tags;
    try {
      tags = await getExif(file);
    } catch (error, stackTrace) {
      _logger.warning("Unable to load file EXIF", error, stackTrace);
      tags = <String, IfdTag>{};
    }
    if (!_disposed) {
      exifTags.value = tags;
      try {
        exifDetails.value = FileDetailsExif.fromTags(tags);
      } catch (error, stackTrace) {
        _logger.warning("Unable to parse file EXIF", error, stackTrace);
        exifDetails.value = FileDetailsExif.fromTags(const {});
      }
    }
    await _persistDiscoveredLocation(locationFromExif(tags));
  }

  Future<void> _loadVideo() async {
    FFProbeProps? metadata;
    try {
      final File? originFile = await getFile(file, isOrigin: true);
      metadata = originFile == null ? null : await getVideoProps(originFile);
    } catch (error, stackTrace) {
      _logger.warning("Unable to load video metadata", error, stackTrace);
    }
    if (!_disposed) {
      videoMetadata.value = metadata ?? (FFProbeProps()..propData = {});
    }
    await _persistDiscoveredLocation(metadata?.location);
  }

  Future<void> _persistDiscoveredLocation(Location? location) async {
    if (file.hasLocation || location == null) return;
    if (!file.isUploaded || file.ownerID != currentUserID) return;
    if (location.latitude == null || location.longitude == null) return;
    try {
      await FileMagicService.instance.updatePublicMagicMetadata(
        [file],
        {latKey: location.latitude, longKey: location.longitude},
      );
      file.location = location;
      if (_disposed) return;
      hasLocation.value = true;
    } catch (error, stackTrace) {
      _logger.severe(
        "Unable to save location discovered in metadata",
        error,
        stackTrace,
      );
    }
  }

  void dispose() {
    _disposed = true;
    exifTags.dispose();
    exifDetails.dispose();
    videoMetadata.dispose();
    hasLocation.dispose();
  }
}
