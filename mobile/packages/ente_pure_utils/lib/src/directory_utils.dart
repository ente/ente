import 'dart:io';

import "package:logging/logging.dart";
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class DirectoryUtils {
  static final logger = Logger('DirectoryUtils');

  static Future<String> getDatabasePath(String databaseName) async {
    String? directoryPath;

    directoryPath ??= (await getApplicationSupportDirectory()).path;

    return p.joinAll([directoryPath, ".$databaseName"]);
  }

  static Future<Directory> getDirectoryForInit() async {
    final directory = await getApplicationCacheDirectory();

    return Directory(p.join(directory.path, "init"));
  }

  static Future<Directory> getTempsDir() async {
    return await getTemporaryDirectory();
  }
}
