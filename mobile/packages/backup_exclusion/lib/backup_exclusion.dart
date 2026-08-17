import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:logging/logging.dart';

final _logger = Logger('BackupExclusion');
const _channel = MethodChannel('io.ente.backup_exclusion');

// Reapply on every app init: device restores recreate directories without it.
Future<void> excludeFromBackup(String path) async {
  if (!Platform.isIOS) return;
  await _invokeExcludeFromBackup(path);
}

@visibleForTesting
Future<void> invokeExcludeFromBackup(String path) =>
    _invokeExcludeFromBackup(path);

Future<void> _invokeExcludeFromBackup(String path) async {
  try {
    final ok = await _channel.invokeMethod<bool>('excludeFromBackup', {
      'path': path,
    });
    if (ok != true) {
      _logger.warning('excludeFromBackup returned false for: $path');
    }
  } on PlatformException catch (e) {
    _logger.warning('Failed to exclude path from backup: $path - ${e.message}');
  } on MissingPluginException {
    // Channel not registered in headless background execution (Workmanager).
    // Safe to ignore: backup exclusion is a best-effort attribute set on
    // foreground init; background tasks do not trigger iCloud backups.
    _logger.info('excludeFromBackup skipped: channel unavailable (background)');
  }
}
