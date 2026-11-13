import "dart:async";
import "dart:io";

import "package:logging/logging.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/db/files_db.dart";
import "package:photos/events/files_updated_event.dart";
import "package:photos/events/local_photos_updated_event.dart";
import "package:photos/main.dart" show isProcessBg;
import "package:photos/models/file/file.dart";
import "package:photos/models/location/location.dart";
import "package:photos/module/download/file.dart";
import "package:photos/module/metadata/exif.dart";
import "package:photos/module/metadata/local_file.dart";
import 'package:photos/module/metadata/location.dart';
import "package:photos/module/metadata/photo.dart";
import "package:photos/service_locator.dart";
import "package:photos/services/process_activity.dart";

class OfflineImportMetadataService {
  static const kProcessingVersion = 3;
  static const kDefaultBatchSize = 25;

  final _logger = Logger("OfflineImportMetadataService");
  final _db = FilesDB.instance;

  Completer<void>? _running;

  OfflineImportMetadataService._privateConstructor();

  static final instance = OfflineImportMetadataService._privateConstructor();

  Future<void> processPendingFiles({int batchSize = kDefaultBatchSize}) async {
    if (!Platform.isAndroid || !isLocalGalleryMode) {
      return;
    }
    if (_running != null) {
      _logger.info("Offline import metadata processing already in progress");
      return _running!.future;
    }

    _running = Completer<void>();
    try {
      ({int creationTime, int generatedID})? cursor;
      while (isLocalGalleryMode) {
        if (isProcessBg && await isForegroundEngineActive()) {
          _logger.info("Foreground active, stopping background processing");
          return;
        }
        final files = await _db.getUnUploadedLocalFilesPendingOfflineProcessing(
          kProcessingVersion,
          limit: batchSize,
          cursor: cursor,
        );
        if (files.isEmpty) {
          return;
        }
        cursor = (
          creationTime: files.last.creationTime!,
          generatedID: files.last.generatedID!,
        );

        final updatedFiles = <EnteFile>[];
        for (final file in files) {
          if (!isLocalGalleryMode) {
            _logger.info(
              "Offline mode disabled during per-file processing, stopping",
            );
            return;
          }
          if ((file.localID ?? "").isEmpty) {
            continue;
          }
          final processed = await _processFile(file);
          if (processed) {
            updatedFiles.add(file);
          }
        }

        if (updatedFiles.isNotEmpty) {
          Bus.instance.fire(
            LocalPhotosUpdatedEvent(
              updatedFiles,
              type: EventType.coverChanged,
              source: "offlineImportMetadata",
            ),
          );
        }

        if (files.length < batchSize) {
          return;
        }
      }
      _logger.info("Offline mode disabled, stopping metadata processing");
    } finally {
      _running?.complete();
      _running = null;
    }
  }

  Future<bool> _processFile(EnteFile file) async {
    try {
      final originFile = await getFile(file, isOrigin: true);
      if (originFile == null || !originFile.existsSync()) {
        return false;
      }

      final fileSize = await originFile.length();
      final metadata = shouldReadExif(file)
          ? await tryReadPhotoMetadata(originFile)
          : null;
      final dimensions = metadata?.dimensions;
      if (dimensions != null) {
        applyDisplayDimensions(file, dimensions.width, dimensions.height);
      }

      await _updateLocationAndDimensions(
        file,
        originFile,
        metadata?.embeddedLocation,
      );

      applyCreationTimeMetadata(file, metadata?.creationDateTime);
      if (metadata != null) {
        applyMediaTypeMetadata(
          file,
          metadata.isPanorama,
          metadata.motionVideoStart?.toInt(),
        );
      }

      final updated = await _db.updateOfflineImportMetadataForLocalID(
        file.localID!,
        processingVersion: kProcessingVersion,
        modificationTime: file.modificationTime!,
        creationTime: file.creationTime,
        location: file.location,
        fileSize: fileSize,
        mediaType: metadata == null ? null : file.pubMagicMetadata!.mediaType,
        motionVideoIndex: metadata == null ? null : file.pubMagicMetadata!.mvi,
        dimensions: file.hasDimensions
            ? (width: file.width, height: file.height)
            : null,
      );
      if (!updated) return false;

      file.fileSize = fileSize;
      file.metadataVersion = kProcessingVersion;
      return true;
    } catch (e, s) {
      _logger.warning("Failed to process ${file.tag}", e, s);
      return false;
    }
  }

  Future<void> _updateLocationAndDimensions(
    EnteFile file,
    File originFile,
    Location? embeddedLocation,
  ) async {
    if (Location.isValidLocation(embeddedLocation)) {
      file.location = embeddedLocation;
    }
    final shouldFetchAssetLocation = !Location.isValidLocation(file.location);
    if (shouldFetchAssetLocation || !file.hasDimensions) {
      final asset = await file.getAsset;
      if (asset != null) {
        if (!file.hasDimensions) {
          applyDisplayDimensions(
            file,
            asset.orientatedWidth,
            asset.orientatedHeight,
          );
        }
        if (shouldFetchAssetLocation) {
          final latLong = await asset.latlngAsync();
          if (latLong != null) {
            file.location = Location(
              latitude: latLong.latitude,
              longitude: latLong.longitude,
            );
          }
        }
      }
    }

    await updateLocationFromEmbeddedMetadata(file, originFile, null);
  }
}
