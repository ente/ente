import "dart:async";
import "dart:io";

import "package:exif_reader/exif_reader.dart";
import "package:logging/logging.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/db/files_db.dart";
import "package:photos/events/files_updated_event.dart";
import "package:photos/events/local_photos_updated_event.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/location/location.dart";
import "package:photos/module/download/file.dart";
import "package:photos/module/metadata/exif.dart";
import "package:photos/module/metadata/local_file.dart";
import 'package:photos/module/metadata/location.dart';
import "package:photos/service_locator.dart";

class OfflineImportMetadataService {
  static const kProcessingVersion = 1;
  static const kDefaultBatchSize = 25;

  final _logger = Logger("OfflineImportMetadataService");
  final _db = FilesDB.instance;

  Completer<void>? _running;

  OfflineImportMetadataService._privateConstructor();

  static final instance = OfflineImportMetadataService._privateConstructor();

  Future<void> processPendingFiles({
    int batchSize = kDefaultBatchSize,
    int maxBatches = 4,
  }) async {
    if (!Platform.isAndroid || !isLocalGalleryMode) {
      return;
    }
    if (_running != null) {
      _logger.info("Offline import metadata processing already in progress");
      return _running!.future;
    }

    _running = Completer<void>();
    try {
      for (var batch = 0; batch < maxBatches; batch++) {
        if (!isLocalGalleryMode) {
          _logger.info("Offline mode disabled, stopping metadata processing");
          return;
        }

        final files = await _db.getUnUploadedLocalFilesPendingOfflineProcessing(
          kProcessingVersion,
          limit: batchSize,
        );
        if (files.isEmpty) {
          return;
        }

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
    } finally {
      _running?.complete();
      _running = null;
    }
  }

  Future<bool> _processFile(EnteFile file) async {
    File? originFile;
    try {
      originFile = await getFile(file, isOrigin: true);
      if (originFile == null || !originFile.existsSync()) {
        return false;
      }

      final fileSize = await originFile.length();
      final exifData = shouldReadExif(file)
          ? await tryExifFromFile(originFile)
          : null;
      final exifTime = exifData != null
          ? await tryParseExifDateTime(null, exifData)
          : null;

      await _updateLocationForOfflineFile(file, originFile, exifData);

      applyCreationTimeMetadata(file, exifTime);

      await _db.updateOfflineImportMetadataForLocalID(
        file.localID!,
        processingVersion: kProcessingVersion,
        creationTime: file.creationTime,
        location: file.location,
        fileSize: fileSize,
      );

      file.fileSize = fileSize;
      file.metadataVersion = kProcessingVersion;
      return true;
    } catch (e, s) {
      _logger.warning("Failed to process ${file.tag}", e, s);
      return false;
    } finally {
      if (Platform.isIOS &&
          originFile != null &&
          !file.isSharedMediaToAppSandbox) {
        try {
          await originFile.delete();
        } catch (_) {}
      }
    }
  }

  Future<void> _updateLocationForOfflineFile(
    EnteFile file,
    File originFile,
    Map<String, IfdTag>? exifData,
  ) async {
    final shouldFetchAssetLocation =
        file.location == null ||
        ((file.location?.latitude ?? 0) == 0 &&
            (file.location?.longitude ?? 0) == 0);
    if (shouldFetchAssetLocation) {
      final asset = await file.getAsset;
      if (asset != null) {
        final latLong = await asset.latlngAsync();
        if (latLong != null) {
          file.location = Location(
            latitude: latLong.latitude,
            longitude: latLong.longitude,
          );
        }
      }
    }

    await updateLocationFromEmbeddedMetadata(file, originFile, exifData);
  }
}
