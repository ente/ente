import 'dart:io';
import 'dart:typed_data';

import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

final _logger = Logger('ImportFileCleanup');

Future<String> readPickedImportFileAsString(String path) async {
  try {
    return await File(path).readAsString();
  } finally {
    await deletePickedImportFileIfAppOwned(path);
  }
}

Future<Uint8List> readPickedImportFileAsBytes(String path) async {
  try {
    return await File(path).readAsBytes();
  } finally {
    await deletePickedImportFileIfAppOwned(path);
  }
}

Future<void> deletePickedImportFileIfAppOwned(String path) async {
  if (!await isAppOwnedPickedImportFile(path)) {
    return;
  }

  try {
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
  } catch (e, s) {
    _logger.warning('Failed to delete picked import file copy', e, s);
  }
}

Future<bool> isAppOwnedPickedImportFile(String path) async {
  if (!Platform.isIOS && !Platform.isAndroid) {
    return false;
  }

  final candidatePath = await _canonicalFilePath(path);
  final appOwnedRoots = await _appOwnedPickedFileRoots();

  for (final root in appOwnedRoots) {
    final rootPath = await _canonicalDirectoryPath(root);
    if (p.isWithin(rootPath, candidatePath)) {
      return true;
    }
  }
  return false;
}

Future<List<String>> _appOwnedPickedFileRoots() async {
  final roots = <String>[];

  if (Platform.isIOS) {
    roots.add(Directory.systemTemp.path);
    await _addDirectoryRoot(roots, getApplicationCacheDirectory);
  } else if (Platform.isAndroid) {
    await _addDirectoryRoot(
      roots,
      getApplicationCacheDirectory,
      child: 'file_picker',
    );
    await _addDirectoryRoot(roots, getTemporaryDirectory, child: 'file_picker');
  }

  return roots.toSet().toList();
}

Future<void> _addDirectoryRoot(
  List<String> roots,
  Future<Directory> Function() directoryProvider, {
  String? child,
}) async {
  try {
    final directory = await directoryProvider();
    roots.add(child == null ? directory.path : p.join(directory.path, child));
  } catch (e, s) {
    _logger.fine('Failed to resolve app-owned import cleanup root', e, s);
  }
}

Future<String> _canonicalFilePath(String path) async {
  try {
    return await File(path).resolveSymbolicLinks();
  } catch (_) {
    return p.normalize(p.absolute(path));
  }
}

Future<String> _canonicalDirectoryPath(String path) async {
  try {
    return await Directory(path).resolveSymbolicLinks();
  } catch (_) {
    return p.normalize(p.absolute(path));
  }
}
