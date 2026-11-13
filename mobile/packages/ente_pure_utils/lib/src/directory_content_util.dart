import 'dart:io';

import "package:ente_pure_utils/src/data_util.dart";
import "package:path/path.dart";

class DirectoryStat {
  final String path;
  final List<DirectoryStat> subDirectory;
  final Map<String, int> fileNameToSize;
  final int size;

  DirectoryStat(this.path, this.subDirectory, this.fileNameToSize, this.size);

  int get total => fileNameToSize.length + subDirectory.length;

  int get fileCount => fileNameToSize.length;
}

const int _oneMB = 1048576;
const int _tenMB = 10485760;
const int _noSuchFileOrDirectoryErrorCode = 2;

String prettyPrintDirectoryStat(
  DirectoryStat dirStat,
  String rootPath, [
  String indent = '',
  int minDirSizeForPrint = _tenMB,
  int minFileSizeForPrint = _oneMB,
]) {
  final StringBuffer buffer = StringBuffer();
  _buildPrettyString(
    dirStat,
    rootPath,
    buffer,
    indent,
    minDirSizeForPrint,
    minFileSizeForPrint,
  );
  return buffer.toString();
}

void _buildPrettyString(
  DirectoryStat dirStat,
  String rootPath,
  StringBuffer buffer,
  String indent,
  int minDirSizeForPrint,
  int minFileSizeForPrint,
) {
  if (dirStat.size < minDirSizeForPrint) {
    return;
  }
  final String relativePath = dirStat.path.replaceFirst(rootPath, '');

  if (relativePath.isEmpty) {
    buffer.writeln(
      'Root: ${basename(dirStat.path)} [SubDir:${dirStat.subDirectory.length} Files:${dirStat.fileNameToSize.length}], Size:${formatBytes(dirStat.size)}',
    );
  } else {
    buffer.writeln(
      '${indent}Directory: $relativePath, [SubDir:${dirStat.subDirectory.length} Files:${dirStat.fileNameToSize.length}], Size: ${formatBytes(dirStat.size)}',
    );
  }

  for (var subDir in dirStat.subDirectory) {
    _buildPrettyString(
      subDir,
      rootPath,
      buffer,
      '$indent  ',
      minDirSizeForPrint,
      minFileSizeForPrint,
    );
  }

  for (var fileName in dirStat.fileNameToSize.keys) {
    final int fSize = dirStat.fileNameToSize[fileName]!;
    if (fSize <= minFileSizeForPrint) {
      continue;
    }
    buffer.writeln('$indent  File: $fileName, Size: ${formatBytes(fSize)}');
  }
}

Future<DirectoryStat> getDirectoryStat(
  Directory directory, {
  String? prefix,
}) async {
  int size = 0;
  final List<DirectoryStat> subDirectories = [];
  final Map<String, int> fileNameToSize = {};

  if (await directory.exists()) {
    final List<FileSystemEntity> entities = directory.listSync();
    for (FileSystemEntity entity in entities) {
      if (prefix != null && !entity.path.contains(prefix)) {
        continue;
      }

      if (entity is File) {
        final int fileSize = await File(entity.path).length();
        size += fileSize;
        fileNameToSize[entity.uri.pathSegments.last] = fileSize;
      } else if (entity is Directory) {
        final DirectoryStat subDirStat = await getDirectoryStat(
          Directory(entity.path),
        );
        subDirectories.add(subDirStat);
        size += subDirStat.size;
      }
    }
  }
  return DirectoryStat(directory.path, subDirectories, fileNameToSize, size);
}

Future<void> deleteDirectoryContents(String directoryPath) async {
  final directory = Directory(directoryPath);
  if (!(await directory.exists())) {
    return;
  }
  final contents = await directory.list().toList();

  for (final fileOrDirectory in contents) {
    await deleteFileSystemEntityIfPresent(
      fileOrDirectory,
      recursive: fileOrDirectory is Directory,
    );
  }
}

Future<bool> deleteFileSystemEntityIfPresent(
  FileSystemEntity entity, {
  bool recursive = false,
}) async {
  try {
    await entity.delete(recursive: recursive);
    return true;
  } on FileSystemException catch (e) {
    if (!isFileSystemPathMissing(e)) {
      rethrow;
    }
    return false;
  }
}

bool isFileSystemPathMissing(FileSystemException e) =>
    e is PathNotFoundException ||
    e.osError?.errorCode == _noSuchFileOrDirectoryErrorCode;

Future<int> getFileSize(String path) async {
  final file = File(path);
  return await file.exists() ? await file.length() : 0;
}
