import 'dart:io';

import 'package:scoped_dir_access/scoped_dir_access.dart';

/// Service for managing iOS security-scoped bookmarks.
///
/// This is a thin wrapper around [DirUtils] for backward compatibility.
/// You can use [DirUtils.instance] directly if you prefer.
class SecurityBookmarkService {
  SecurityBookmarkService._();

  static final SecurityBookmarkService instance = SecurityBookmarkService._();

  final _dirUtils = DirUtils.instance;

  /// Opens native iOS directory picker and creates a bookmark immediately.
  ///
  /// Returns a [DirectoryPickResult] with both path and bookmark, or null if cancelled.
  /// This is the preferred method on iOS as it creates the bookmark while we still
  /// have the security-scoped URL from the picker.
  Future<DirectoryPickResult?> pickDirectoryAndCreateBookmark() async {
    if (!Platform.isIOS) return null;

    final result = await _dirUtils.pickDirectory();
    if (result == null) return null;

    return DirectoryPickResult(
      path: result.path,
      bookmark: result.bookmark ?? '',
    );
  }

  /// Starts accessing a security-scoped resource using a stored bookmark.
  ///
  /// Returns a [BookmarkAccessResult] containing the success status,
  /// resolved path, and whether the bookmark is stale.
  ///
  /// You MUST call [stopAccessingBookmark] when done to balance the call.
  Future<BookmarkAccessResult?> startAccessingBookmark(String bookmark) async {
    if (!Platform.isIOS) return null;

    final dir = PickedDirectory(path: '', bookmark: bookmark);
    final result = await _dirUtils.startAccess(dir);
    if (result == null) return null;

    return BookmarkAccessResult(
      success: result.success,
      path: result.path,
      isStale: result.isStale,
    );
  }

  /// Stops accessing a security-scoped resource.
  ///
  /// Always call this after you're done with file operations to
  /// balance the [startAccessingBookmark] call.
  Future<bool> stopAccessingBookmark(String bookmark) async {
    if (!Platform.isIOS) return true;

    final dir = PickedDirectory(path: '', bookmark: bookmark);
    return _dirUtils.stopAccess(dir);
  }
}

class DirectoryPickResult {
  const DirectoryPickResult({required this.path, required this.bookmark});

  final String path;
  final String bookmark;
}

class BookmarkAccessResult {
  const BookmarkAccessResult({
    required this.success,
    required this.path,
    required this.isStale,
  });

  final bool success;
  final String path;
  final bool isStale;
}
