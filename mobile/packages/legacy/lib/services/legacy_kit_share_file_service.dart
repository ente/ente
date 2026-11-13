import "dart:io";

import "package:logging/logging.dart";
import "package:path_provider/path_provider.dart";

const legacyKitShareDirectoryPrefix = "ente_legacy_kit_share_";
const legacyKitShareFilePrefix = "ente-legacy-kit-";
const legacyKitShareRetention = Duration(minutes: 5);

final _logger = Logger("LegacyKitShareFiles");

Future<void> cleanStaleLegacyKitShareFiles() async {
  final cleanupStartedAt = DateTime.now();
  await Future<void>.delayed(legacyKitShareRetention);
  try {
    final temporaryDirectory = await getTemporaryDirectory();
    await for (final entity in temporaryDirectory.list(followLinks: false)) {
      if (entity is Directory &&
          _entityName(entity).startsWith(legacyKitShareDirectoryPrefix)) {
        await deleteLegacyKitShareFile(
          entity,
          modifiedBefore: cleanupStartedAt,
        );
      }
    }

    final sharePlusDirectory = Directory(
      "${temporaryDirectory.path}/share_plus",
    );
    if (!await sharePlusDirectory.exists()) {
      return;
    }
    await for (final entity in sharePlusDirectory.list(followLinks: false)) {
      final name = _entityName(entity);
      if (entity is File &&
          name.startsWith(legacyKitShareFilePrefix) &&
          name.endsWith(".pdf")) {
        await deleteLegacyKitShareFile(
          entity,
          modifiedBefore: cleanupStartedAt,
        );
      }
    }
  } catch (e, s) {
    _logger.warning("Failed to clean stale Legacy Kit share files", e, s);
  }
}

Future<void> deleteLegacyKitShareFile(
  FileSystemEntity entity, {
  DateTime? modifiedBefore,
}) async {
  try {
    if (!await entity.exists()) {
      return;
    }
    if (modifiedBefore != null &&
        (await entity.stat()).modified.isAfter(modifiedBefore)) {
      return;
    }
    await entity.delete(recursive: entity is Directory);
  } catch (e, s) {
    _logger.warning("Failed to delete a Legacy Kit share file", e, s);
  }
}

String _entityName(FileSystemEntity entity) =>
    entity.uri.pathSegments.lastWhere((segment) => segment.isNotEmpty);
