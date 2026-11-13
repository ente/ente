import 'dart:io';

import 'package:scoped_dir_access/scoped_dir_access.dart';

// Backward-compatible wrapper; new code can use DirUtils directly.
class SecurityBookmarkService {
  SecurityBookmarkService._();

  static final SecurityBookmarkService instance = SecurityBookmarkService._();

  final _dirUtils = DirUtils.instance;

  // Create the bookmark while the picker still owns the security-scoped URL.
  Future<DirectoryPickResult?> pickDirectoryAndCreateBookmark() async {
    if (!Platform.isIOS) return null;

    final result = await _dirUtils.pickDirectory();
    if (result == null) return null;

    return DirectoryPickResult(
      path: result.path,
      bookmark: result.bookmark ?? '',
    );
  }

  // Each successful call must be balanced with stopAccessingBookmark.
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
