import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:ente_auth/core/configuration.dart';
import 'package:ente_auth/models/export/ente.dart';
import 'package:ente_auth/store/code_store.dart';
import 'package:ente_crypto_api/ente_crypto_api.dart';
import 'package:ente_events/event_bus.dart';
import 'package:ente_events/models/signed_out_event.dart';
import 'package:intl/intl.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:scoped_dir_access/scoped_dir_access.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocalBackupService {
  LocalBackupService._();

  final _logger = Logger('LocalBackupService');
  static final LocalBackupService instance = LocalBackupService._();

  static const int _maxBackups = 5;
  static const _lastBackupDayKey = 'lastBackupDay';
  static const _iosBookmarkKey = 'autoBackupIosBookmark';

  Future<void> init({bool hasOptedForOfflineMode = false}) async {
    await _clearBackupPasswordIfFreshInstall(hasOptedForOfflineMode);

    Bus.instance.on<SignedOutEvent>().listen((event) {
      _clearBackupPassword();
    });
  }

  /// Clear backup password on fresh install (like lock screen does).
  /// Only clears if not logged in and not in offline mode.
  Future<void> _clearBackupPasswordIfFreshInstall(
    bool hasOptedForOfflineMode,
  ) async {
    if (!Configuration.instance.isLoggedIn() && !hasOptedForOfflineMode) {
      await _clearBackupPassword();
    }
  }

  Future<void> _clearBackupPassword() async {
    await Configuration.instance.clearBackupPassword();
  }

  Future<bool> triggerAutomaticBackup({bool isManual = false}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!_isBackupEnabled(prefs)) return false;
      if (!isManual && _hasBackedUpToday(prefs)) return false;

      final _BackupTarget? target = _resolveTarget(prefs);
      if (target == null) return false;

      final String? password = await _readPassword();
      if (password == null || password.isEmpty) {
        _logger.warning('Automatic backup skipped: password not set.');
        return false;
      }

      final String? encryptedJson = await _buildEncryptedPayload(password);
      if (encryptedJson == null) return false;

      final now = DateTime.now();
      final fileName = _buildFileName(now, isManual: isManual);
      final writeSuccess = await _writeBackup(
        target: target,
        fileName: fileName,
        content: encryptedJson,
      );

      if (writeSuccess && !isManual) {
        await _recordBackupDay(prefs, now);
      }
      return writeSuccess;
    } catch (e, s) {
      if (isManual) {
        _logger.severe('Manual backup failed', e, s);
        rethrow;
      }
      _logger.severe('Silent error during automatic backup', e, s);
      return false;
    }
  }

  Future<bool> triggerDailyBackupIfNeeded() async {
    final prefs = await SharedPreferences.getInstance();
    if (_hasBackedUpToday(prefs)) return false;
    return triggerAutomaticBackup();
  }

  /// Write backup to a directory that we already have scoped access to.
  /// Used on iOS where security-scoped access is held by caller.
  Future<bool> writeBackupToDirectory(String directoryPath) async {
    try {
      final String? password = await _readPassword();
      if (password == null || password.isEmpty) {
        _logger.warning('Backup skipped: password not set.');
        return false;
      }

      final String? encryptedJson = await _buildEncryptedPayload(password);
      if (encryptedJson == null) {
        _logger.warning('Backup skipped: no data to backup.');
        return false;
      }

      final now = DateTime.now();
      final fileName = _buildFileName(now, isManual: true);
      final filePath = '$directoryPath/$fileName';

      final backupFile = File(filePath);
      await backupFile.writeAsString(encryptedJson);

      await _manageOldBackups(directoryPath);

      final prefs = await SharedPreferences.getInstance();
      await _recordBackupDay(prefs, now);

      return true;
    } catch (e, s) {
      _logger.severe('Failed to write backup to directory: $e', e, s);
      return false;
    }
  }

  Future<bool> _writeBackup({
    required _BackupTarget target,
    required String fileName,
    required String content,
  }) async {
    try {
      final dirUtils = DirUtils.instance;
      final contentBytes = Uint8List.fromList(utf8.encode(content));

      // Android SAF
      if (target.treeUri != null) {
        final dir = PickedDirectory(path: '', treeUri: target.treeUri);
        final success = await dirUtils.writeFile(dir, fileName, contentBytes);
        if (success) {
          await _pruneBackups(dir, limit: _maxBackups);
        }
        return success;
      }

      // iOS/macOS with bookmark - write directly to the selected directory
      if ((Platform.isIOS || Platform.isMacOS) && target.iosBookmark != null) {
        final dir = PickedDirectory(
          path: target.path!,
          bookmark: target.iosBookmark,
        );
        final result = await dirUtils.withAccess(dir, (path) async {
          final success = await dirUtils.writeFile(
            PickedDirectory(path: path, bookmark: target.iosBookmark),
            fileName,
            contentBytes,
          );
          if (success) {
            await _manageOldBackups(path);
          }
          return success;
        });
        return result ?? false;
      }

      // Other platforms (Windows, Linux): direct file write
      final basePath = target.path!;
      await Directory(basePath).create(recursive: true);
      final filePath = '$basePath/$fileName';
      await File(filePath).writeAsBytes(contentBytes);
      await _manageOldBackups(basePath);
      return true;
    } catch (e, s) {
      _logger.severe('Failed to write backup: $e', e, s);
      return false;
    }
  }

  Future<void> _pruneBackups(PickedDirectory dir, {required int limit}) async {
    try {
      final dirUtils = DirUtils.instance;
      final files = await dirUtils.listFiles(dir);
      final backupFiles = files
          .where((file) => !file.isDirectory && _isBackupFile(file.name))
          .toList();

      backupFiles.sort((a, b) {
        final timeCompare = a.lastModified.compareTo(b.lastModified);
        if (timeCompare != 0) return timeCompare;
        return a.name.compareTo(b.name);
      });

      while (backupFiles.length > limit) {
        final file = backupFiles.removeAt(0);
        await dirUtils.deleteFile(dir, file);
      }
    } catch (e, s) {
      _logger.severe('Error pruning backups', e, s);
    }
  }

  Future<void> _manageOldBackups(String backupPath) async {
    try {
      final directory = Directory(backupPath);
      final entities = await directory.list().toList();
      final files = entities
          .whereType<File>()
          .where((f) => _isBackupFile(p.basename(f.path)))
          .toList();

      // Sort by mtime async
      final filesWithMtime = await Future.wait(
        files.map((f) async => (f, await f.lastModified())),
      );
      filesWithMtime.sort((a, b) {
        final cmp = a.$2.compareTo(b.$2);
        return cmp != 0 ? cmp : a.$1.path.compareTo(b.$1.path);
      });

      final sorted = filesWithMtime.map((e) => e.$1).toList();
      while (sorted.length > _maxBackups) {
        await sorted.removeAt(0).delete();
      }
    } catch (e, s) {
      _logger.severe('Error during old backup cleanup', e, s);
    }
  }

  Future<void> deleteAllBackupsIn(String path, {String? iosBookmark}) async {
    try {
      final dirUtils = DirUtils.instance;
      final backupPath = path;

      Future<void> doDelete() async {
        final backupDir = Directory(backupPath);
        if (!await backupDir.exists()) {
          _logger.warning('Old backup directory not found. Nothing to delete.');
          return;
        }

        final entities = await backupDir.list().toList();
        final files = entities
            .whereType<File>()
            .where((f) => _isBackupFile(p.basename(f.path)))
            .toList();

        if (files.isEmpty) {
          _logger.info('No old backup files found to delete.');
          return;
        }

        for (final file in files) {
          await file.delete();
        }
      }

      // On iOS/macOS, use scoped access via bookmark
      if ((Platform.isIOS || Platform.isMacOS) &&
          iosBookmark != null &&
          iosBookmark.isNotEmpty) {
        final dir = PickedDirectory(path: path, bookmark: iosBookmark);
        await dirUtils.withAccess(dir, (_) async {
          await doDelete();
          return true;
        });
      } else {
        await doDelete();
      }
    } catch (e, s) {
      _logger.severe('Error during full backup cleanup of old directory', e, s);
    }
  }

  bool _isBackupEnabled(SharedPreferences prefs) =>
      prefs.getBool('isAutoBackupEnabled') ?? false;

  _BackupTarget? _resolveTarget(SharedPreferences prefs) {
    final path = prefs.getString('autoBackupPath');
    final treeUri = prefs.getString('autoBackupTreeUri');
    final iosBookmark = prefs.getString(_iosBookmarkKey);

    if (treeUri != null && treeUri.isNotEmpty) {
      return _BackupTarget.saf(treeUri);
    }
    if (path != null && path.isNotEmpty) {
      return _BackupTarget.file(path, iosBookmark: iosBookmark);
    }
    return null;
  }

  Future<String?> _readPassword() async {
    try {
      return Configuration.instance.getBackupPassword();
    } catch (e, s) {
      _logger.severe('Unable to read backup password', e, s);
      return null;
    }
  }

  Future<String?> _buildEncryptedPayload(String password) async {
    final rawContent = await CodeStore.instance.getCodesForExport();
    final cleanedLines = rawContent
        .split('\n')
        .map((line) {
          if (line.trim().isEmpty) return null;
          if (line.startsWith('"') && line.endsWith('"')) {
            return jsonDecode(line);
          }
          return line;
        })
        .whereType<String>()
        .toList();

    final plainTextContent = cleanedLines.join('\n');
    if (plainTextContent.trim().isEmpty) {
      return null;
    }

    final kekSalt = CryptoUtil.getSaltToDeriveKey();
    final derivedKeyResult = await CryptoUtil.deriveSensitiveKey(
      utf8.encode(password),
      kekSalt,
    );

    final encResult = await CryptoUtil.encryptData(
      utf8.encode(plainTextContent),
      derivedKeyResult.key,
    );

    final encContent = CryptoUtil.bin2base64(encResult.encryptedData!);
    final encNonce = CryptoUtil.bin2base64(encResult.header!);

    final data = EnteAuthExport(
      version: 1,
      encryptedData: encContent,
      encryptionNonce: encNonce,
      kdfParams: KDFParams(
        memLimit: derivedKeyResult.memLimit,
        opsLimit: derivedKeyResult.opsLimit,
        salt: CryptoUtil.bin2base64(kekSalt),
      ),
    );

    return jsonEncode(data.toJson());
  }

  String _buildFileName(DateTime now, {required bool isManual}) {
    final formatter = DateFormat('yyyy-MM-dd_HH-mm-ss');
    final formattedDate = formatter.format(now);
    return isManual
        ? 'ente-auth-manual-backup-$formattedDate.json'
        : 'ente-auth-daily-backup-$formattedDate.json';
  }

  bool _hasBackedUpToday(SharedPreferences prefs) {
    final todayKey = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final last = prefs.getString(_lastBackupDayKey);
    return last == todayKey;
  }

  Future<void> _recordBackupDay(SharedPreferences prefs, DateTime now) async {
    final dayKey = DateFormat('yyyy-MM-dd').format(now);
    await prefs.setString(_lastBackupDayKey, dayKey);
  }

  bool _isBackupFile(String fileName) {
    return fileName.startsWith('ente-auth-daily-backup-') ||
        fileName.startsWith('ente-auth-manual-backup-') ||
        fileName.startsWith('ente-auth-auto-backup-');
  }
}

class _BackupTarget {
  const _BackupTarget.file(this.path, {this.iosBookmark}) : treeUri = null;
  const _BackupTarget.saf(this.treeUri) : path = null, iosBookmark = null;

  final String? path;
  final String? treeUri;
  final String? iosBookmark;

  bool get isSaf => treeUri != null;
}
