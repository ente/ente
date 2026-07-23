/// Cross-platform directory utilities with persistent access support.
///
/// - iOS: Uses security-scoped bookmarks for persistent directory access
/// - Android: Uses Storage Access Framework (SAF) via saf_util/saf_stream
/// - Other platforms: Uses standard file system access via file_picker
library;

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:saf_stream/saf_stream.dart';
import 'package:saf_util/saf_util.dart';

final _logger = Logger('DirUtils');

/// Represents a picked directory with platform-specific access credentials.
class PickedDirectory {
  const PickedDirectory({required this.path, this.bookmark, this.treeUri});

  /// The display path of the directory.
  final String path;

  /// iOS security-scoped bookmark (base64 encoded). Null on other platforms.
  final String? bookmark;

  /// Android SAF tree URI. Null on other platforms.
  final String? treeUri;

  /// Returns true if this directory has a security-scoped bookmark (iOS or macOS).
  bool get hasBookmark => bookmark != null;
  bool get isAndroid => treeUri != null;
}

/// Result from starting security-scoped access on iOS.
class AccessResult {
  const AccessResult({
    required this.success,
    required this.path,
    required this.isStale,
  });

  final bool success;
  final String path;
  final bool isStale;
}

/// Information about a file in a directory.
class FileInfo {
  const FileInfo({
    required this.name,
    required this.path,
    required this.isDirectory,
    required this.lastModified,
    this.uri,
  });

  final String name;
  final String path;
  final bool isDirectory;
  final DateTime lastModified;

  /// Android SAF URI (for deletion). Null on other platforms.
  final String? uri;
}

/// Cross-platform directory utilities.
class DirUtils {
  DirUtils._();

  static final DirUtils instance = DirUtils._();
  static const _channel = MethodChannel('io.ente.scoped_dir_access');

  // ============================================================
  // Directory Picker
  // ============================================================

  /// Pick a directory with persistent access.
  ///
  /// On iOS, this opens the native document picker and creates a security-scoped
  /// bookmark for persistent access across app launches.
  ///
  /// On Android, this opens SAF directory picker with persistent permissions.
  ///
  /// On other platforms, this uses file_picker.
  ///
  /// Returns null if the user cancels.
  Future<PickedDirectory?> pickDirectory() async {
    if (Platform.isIOS) {
      return _pickDirectoryIos();
    } else if (Platform.isAndroid) {
      return _pickDirectoryAndroid();
    } else if (Platform.isMacOS) {
      return _pickDirectoryMacOS();
    } else {
      return _pickDirectoryOther();
    }
  }

  Future<PickedDirectory?> _pickDirectoryIos() async {
    try {
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'pickDirectory',
      );
      if (result == null) return null;

      final path = result['path'] as String?;
      final bookmark = result['bookmark'] as String?;

      if (path == null || bookmark == null) {
        _logger.severe('iOS: Invalid result from directory picker');
        return null;
      }

      return PickedDirectory(path: path, bookmark: bookmark);
    } on PlatformException catch (e) {
      _logger.severe('iOS: Failed to pick directory: ${e.message}');
      return null;
    }
  }

  Future<PickedDirectory?> _pickDirectoryAndroid() async {
    try {
      final saf = SafUtil();
      final picked = await saf.pickDirectory(
        writePermission: true,
        persistablePermission: true,
      );
      if (picked == null) return null;

      return PickedDirectory(path: picked.name, treeUri: picked.uri);
    } catch (e) {
      _logger.severe('Android: Failed to pick directory: $e');
      return null;
    }
  }

  Future<PickedDirectory?> _pickDirectoryMacOS() async {
    try {
      // Use file_picker to pick the directory
      final path = await FilePicker.platform.getDirectoryPath();
      if (path == null) return null;

      // Create a security-scoped bookmark from the picked path
      // This must be done while we still have access (same session as picker)
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'createBookmarkFromPath',
        {'path': path},
      );

      if (result == null) {
        _logger.severe('macOS: Failed to create bookmark for path: $path');
        return null;
      }

      final bookmark = result['bookmark'] as String?;
      if (bookmark == null) {
        _logger.severe('macOS: Invalid result from createBookmarkFromPath');
        return null;
      }

      return PickedDirectory(path: path, bookmark: bookmark);
    } on PlatformException catch (e) {
      _logger.severe('macOS: Failed to pick directory: ${e.message}');
      return null;
    } catch (e) {
      _logger.severe('macOS: Failed to pick directory: $e');
      return null;
    }
  }

  Future<PickedDirectory?> _pickDirectoryOther() async {
    try {
      final path = await FilePicker.platform.getDirectoryPath();
      if (path == null) return null;

      return PickedDirectory(path: path);
    } catch (e) {
      _logger.severe('Other: Failed to pick directory: $e');
      return null;
    }
  }

  // ============================================================
  // Security-Scoped Access (iOS/macOS)
  // ============================================================

  /// Start accessing a security-scoped resource (iOS/macOS).
  ///
  /// You MUST call [stopAccess] when done to balance this call.
  /// On platforms without bookmark support, this is a no-op that returns success.
  Future<AccessResult?> startAccess(PickedDirectory dir) async {
    if (!Platform.isIOS && !Platform.isMacOS) {
      return AccessResult(success: true, path: dir.path, isStale: false);
    }

    if (dir.bookmark == null) {
      _logger.severe(
        '${Platform.operatingSystem}: No bookmark available for startAccess',
      );
      return null;
    }

    try {
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'startAccess',
        {'bookmark': dir.bookmark},
      );
      if (result == null) return null;

      return AccessResult(
        success: result['success'] as bool,
        path: result['path'] as String,
        isStale: result['isStale'] as bool,
      );
    } on PlatformException catch (e) {
      _logger.severe('${Platform.operatingSystem}: Failed to start access: $e');
      return null;
    }
  }

  /// Stop accessing a security-scoped resource (iOS/macOS).
  ///
  /// On platforms without bookmark support, this is a no-op.
  Future<bool> stopAccess(PickedDirectory dir) async {
    if (!Platform.isIOS && !Platform.isMacOS) return true;

    if (dir.bookmark == null) {
      _logger.severe(
        '${Platform.operatingSystem}: No bookmark available for stopAccess',
      );
      return false;
    }

    try {
      final result = await _channel.invokeMethod<bool>('stopAccess', {
        'bookmark': dir.bookmark,
      });
      return result ?? false;
    } on PlatformException catch (e) {
      _logger.severe('${Platform.operatingSystem}: Failed to stop access: $e');
      return false;
    }
  }

  /// Execute a function with security-scoped access.
  ///
  /// Automatically calls startAccess before and stopAccess after.
  /// On platforms without bookmark support, just executes the function directly.
  Future<T?> withAccess<T>(
    PickedDirectory dir,
    Future<T> Function(String path) action,
  ) async {
    final accessResult = await startAccess(dir);
    if (accessResult == null || !accessResult.success) {
      _logger.severe('Failed to start access for: ${dir.path}');
      return null;
    }

    try {
      return await action(accessResult.path);
    } finally {
      await stopAccess(dir);
    }
  }

  // ============================================================
  // File Operations
  // ============================================================

  /// Write a file to the directory.
  ///
  /// [dir] - The picked directory
  /// [fileName] - Name of the file to create
  /// [content] - File content as bytes
  /// [subPath] - Optional subdirectory path within the directory
  Future<bool> writeFile(
    PickedDirectory dir,
    String fileName,
    Uint8List content, {
    String? subPath,
  }) async {
    if (Platform.isAndroid && dir.treeUri != null) {
      return _writeFileAndroid(dir.treeUri!, fileName, content);
    } else if ((Platform.isIOS || Platform.isMacOS) && dir.bookmark != null) {
      return _writeFileWithBookmark(dir, fileName, content, subPath: subPath);
    } else {
      return _writeFileOther(dir.path, fileName, content, subPath: subPath);
    }
  }

  Future<bool> _writeFileAndroid(
    String treeUri,
    String fileName,
    Uint8List content,
  ) async {
    try {
      final safStream = SafStream();
      await safStream.writeFileBytes(
        treeUri,
        fileName,
        'application/octet-stream',
        content,
        overwrite: true,
      );
      return true;
    } catch (e) {
      _logger.severe('Android: Failed to write file: $e');
      return false;
    }
  }

  Future<bool> _writeFileWithBookmark(
    PickedDirectory dir,
    String fileName,
    Uint8List content, {
    String? subPath,
  }) async {
    try {
      final basePath = subPath != null ? '${dir.path}/$subPath' : dir.path;
      final filePath = '$basePath/$fileName';

      final result = await _channel.invokeMethod<bool>('writeFile', {
        'path': filePath,
        'content': content,
      });
      return result ?? false;
    } on PlatformException catch (e) {
      _logger.severe(
        '${Platform.operatingSystem}: Failed to write file: ${e.message}',
      );
      return false;
    }
  }

  Future<bool> _writeFileOther(
    String basePath,
    String fileName,
    Uint8List content, {
    String? subPath,
  }) async {
    try {
      final dirPath = subPath != null ? '$basePath/$subPath' : basePath;
      final filePath = '$dirPath/$fileName';
      await File(filePath).writeAsBytes(content);
      return true;
    } catch (e) {
      _logger.severe('Other: Failed to write file: $e');
      return false;
    }
  }

  /// List files in a directory.
  Future<List<FileInfo>> listFiles(
    PickedDirectory dir, {
    String? subPath,
  }) async {
    if (Platform.isAndroid && dir.treeUri != null) {
      return _listFilesAndroid(dir.treeUri!);
    } else if ((Platform.isIOS || Platform.isMacOS) && dir.bookmark != null) {
      return _listFilesWithBookmark(dir, subPath: subPath);
    } else {
      return _listFilesOther(dir.path, subPath: subPath);
    }
  }

  Future<List<FileInfo>> _listFilesAndroid(String treeUri) async {
    try {
      final safUtil = SafUtil();
      final entries = await safUtil.list(treeUri);
      return entries
          .map(
            (e) => FileInfo(
              name: e.name,
              path: e.uri,
              isDirectory: e.isDir,
              lastModified: DateTime.fromMillisecondsSinceEpoch(e.lastModified),
              uri: e.uri,
            ),
          )
          .toList();
    } catch (e) {
      _logger.severe('Android: Failed to list files: $e');
      return [];
    }
  }

  Future<List<FileInfo>> _listFilesWithBookmark(
    PickedDirectory dir, {
    String? subPath,
  }) async {
    try {
      final basePath = subPath != null ? '${dir.path}/$subPath' : dir.path;
      final result = await _channel.invokeMethod<List<dynamic>>('listFiles', {
        'path': basePath,
      });
      if (result == null) return [];

      return result.map((e) {
        final map = e as Map<dynamic, dynamic>;
        return FileInfo(
          name: map['name'] as String,
          path: map['path'] as String,
          isDirectory: map['isDirectory'] as bool,
          lastModified: DateTime.fromMillisecondsSinceEpoch(
            map['lastModified'] as int,
          ),
        );
      }).toList();
    } on PlatformException catch (e) {
      _logger.severe(
        '${Platform.operatingSystem}: Failed to list files: ${e.message}',
      );
      return [];
    }
  }

  Future<List<FileInfo>> _listFilesOther(
    String basePath, {
    String? subPath,
  }) async {
    try {
      final dirPath = subPath != null ? '$basePath/$subPath' : basePath;
      final dir = Directory(dirPath);
      if (!await dir.exists()) return [];

      final entries = await dir.list().toList();
      return Future.wait(
        entries.map((e) async {
          final stat = await e.stat();
          return FileInfo(
            name: p.basename(e.path),
            path: e.path,
            isDirectory: stat.type == FileSystemEntityType.directory,
            lastModified: stat.modified,
          );
        }),
      );
    } catch (e) {
      _logger.severe('Other: Failed to list files: $e');
      return [];
    }
  }

  /// Delete a file.
  ///
  /// For Android SAF, pass the file's URI as [filePathOrUri].
  /// For other platforms, pass the file path.
  Future<bool> deleteFile(PickedDirectory dir, FileInfo file) async {
    if (Platform.isAndroid && file.uri != null) {
      return _deleteFileAndroid(file.uri!, file.isDirectory);
    } else {
      return _deleteFileOther(file.path);
    }
  }

  Future<bool> _deleteFileAndroid(String uri, bool isDir) async {
    try {
      await SafUtil().delete(uri, isDir);
      return true;
    } catch (e) {
      _logger.severe('Android: Failed to delete: $e');
      return false;
    }
  }

  Future<bool> _deleteFileOther(String path) async {
    try {
      if (Platform.isIOS || Platform.isMacOS) {
        final result = await _channel.invokeMethod<bool>('deleteFile', {
          'path': path,
        });
        return result ?? false;
      } else {
        await File(path).delete();
        return true;
      }
    } catch (e) {
      _logger.severe('Failed to delete: $e');
      return false;
    }
  }
}
