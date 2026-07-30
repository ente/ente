import "dart:math";

import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:logging/logging.dart";
import "package:path/path.dart";
import "package:photo_manager/photo_manager.dart";
import "package:photos/core/constants.dart";

final _logger = Logger("AssetDateTimes");

// Dart DateTime accepts +/- 8.64e15 milliseconds; photo_manager exposes
// timestamps as whole seconds.
const _maxDateTimeSecondsSinceEpoch = 8640000000000;
const _minDateTimeSecondsSinceEpoch = -_maxDateTimeSecondsSinceEpoch;

typedef AssetDateTimes = ({int creationTime, int modificationTime});

/// Compares at the whole-second precision provided by photo_manager.
///
/// Uses the raw asset timestamps, counting invalid ones as epoch, so that
/// assets with broken dates are picked up during first import (cutoff 0) but
/// not re-flagged as updated on every incremental sync.
bool isAssetAtOrAfterSyncCutoff(AssetEntity asset, int cutoffTime) {
  final latestAssetTimeSecond = max(
    _validSecondsSinceEpoch(asset.createDateSecond) ?? 0,
    _validSecondsSinceEpoch(asset.modifiedDateSecond) ?? 0,
  );
  final cutoffTimeSecond = cutoffTime ~/ Duration.microsecondsPerSecond;
  return latestAssetTimeSecond >= cutoffTimeSecond;
}

AssetDateTimes resolveAssetDateTimes(AssetEntity asset) {
  final uploadTime = DateTime.now().toUtc().microsecondsSinceEpoch;
  final creationTime = _validMicrosecondsSinceEpoch(asset.createDateSecond);
  final modificationTime = _validMicrosecondsSinceEpoch(
    asset.modifiedDateSecond,
  );

  if (creationTime == null || modificationTime == null) {
    _logger.warning(
      "LocalID: ${asset.id} has invalid raw date(s) "
      "(createDateSecond: ${asset.createDateSecond}, "
      "modifiedDateSecond: ${asset.modifiedDateSecond}); using fallbacks",
    );
  }

  // A missing creation time is treated as pre-1981 so the filename and
  // modification-time fallbacks in _resolveCreationTime apply to it.
  final resolvedCreationTime = _resolveCreationTime(
    asset,
    creationTime ?? 0,
    modificationTime ?? 0,
    uploadTime,
  );
  return (
    creationTime: resolvedCreationTime,
    modificationTime: modificationTime ?? resolvedCreationTime,
  );
}

int _resolveCreationTime(
  AssetEntity asset,
  int creationTime,
  int modificationTime,
  int uploadTime,
) {
  var resolvedCreationTime = creationTime;
  if (creationTime >= jan011981Time) {
    // Copied files can retain an older modification time while gaining a new
    // filesystem creation time. Embedded metadata may replace this on upload.
    if (modificationTime >= jan011981Time && modificationTime < creationTime) {
      _logger.info(
        "LocalID: ${asset.id} modification time is less than creation time. "
        "Using modification time as creation time",
      );
      resolvedCreationTime = modificationTime;
    }
    return resolvedCreationTime;
  }

  resolvedCreationTime = modificationTime >= jan011981Time
      ? modificationTime
      : uploadTime;
  try {
    final parsedDateTime = parseDateTimeFromFileNameV2(
      basenameWithoutExtension(asset.title ?? ""),
    );
    return parsedDateTime?.microsecondsSinceEpoch ?? resolvedCreationTime;
  } catch (_) {
    return resolvedCreationTime;
  }
}

int? _validSecondsSinceEpoch(int? secondsSinceEpoch) {
  if (secondsSinceEpoch == null ||
      secondsSinceEpoch < _minDateTimeSecondsSinceEpoch ||
      secondsSinceEpoch > _maxDateTimeSecondsSinceEpoch) {
    return null;
  }
  return secondsSinceEpoch;
}

int? _validMicrosecondsSinceEpoch(int? secondsSinceEpoch) {
  final validSeconds = _validSecondsSinceEpoch(secondsSinceEpoch);
  if (validSeconds == null) {
    return null;
  }
  return validSeconds * Duration.microsecondsPerSecond;
}
