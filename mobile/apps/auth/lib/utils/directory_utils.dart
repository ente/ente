import 'dart:io';

import 'package:io/io.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xdg_directories/xdg_directories.dart';

class DirectoryUtils {
  static final logger = Logger('DirectoryUtils');

  static Future<String> getDatabasePath(String databaseName) async {
    String? directoryPath;

    directoryPath ??= (await getApplicationSupportDirectory()).path;

    return p.joinAll([directoryPath, ".$databaseName"]);
  }

  static Future<Directory> getDirectoryForInit() async {
    Directory directory = await getApplicationCacheDirectory();

    return Directory(p.join(directory.path, "enteauthinit"));
  }

  static Future<Directory> getTempsDir() async {
    return await getTemporaryDirectory();
  }

  static String migratedNamingChanges = "migrated_naming_changes.b5";
  static Future<void> migrateNamingChanges() async {
    try {
      final sharedPrefs = await SharedPreferences.getInstance();
      if (sharedPrefs.containsKey(migratedNamingChanges)) {
        return;
      }
      var databaseFile = File(
        p.join(
          (await getApplicationDocumentsDirectory()).path,
          "ente",
          ".ente.authenticator.db",
        ),
      );
      var offlineDatabaseFile = File(
        p.join(
          (await getApplicationDocumentsDirectory()).path,
          "ente",
          ".ente.offline_authenticator.db",
        ),
      );
      Directory oldDataDir;
      Directory newDataDir = await getApplicationSupportDirectory();
      await newDataDir.create(recursive: true);

      if (Platform.isLinux) {
        oldDataDir = Directory(p.join(dataHome.path, "ente_auth"));
        Directory tempDir = Directory(p.join(dataHome.path, "enteauth"));
        if (tempDir.existsSync()) {
          oldDataDir = tempDir;
        }
        if (await oldDataDir.exists()) {
          await copyPath(oldDataDir.path, newDataDir.path);
        }
      } else if (Platform.isWindows) {
        oldDataDir = Directory(
          p.join((await getApplicationDocumentsDirectory()).path, "ente"),
        );
        Directory tempDir = Directory(
          p.join((await getApplicationDocumentsDirectory()).path, "enteauth"),
        );
        if (tempDir.existsSync()) {
          oldDataDir = tempDir;
          databaseFile = File(p.join(tempDir.path, ".ente.authenticator.db"));
          offlineDatabaseFile = File(
            p.join(tempDir.path, ".ente.offline_authenticator.db"),
          );
        }
      } else {
        oldDataDir = await getApplicationDocumentsDirectory();
        databaseFile = File(
          p.join(
            (await getApplicationDocumentsDirectory()).path,
            "ente.authenticator.db",
          ),
        );
        offlineDatabaseFile = File(
          p.join(
            (await getApplicationDocumentsDirectory()).path,
            "ente.offline_authenticator.db",
          ),
        );
      }

      final prefix = Platform.isMacOS ? "" : ".";
      File newDatabaseFile = File(
        p.join(newDataDir.path, "${prefix}ente.authenticator.db"),
      );
      if (await databaseFile.exists() && !await newDatabaseFile.exists()) {
        await databaseFile.copy(newDatabaseFile.path);
      }

      File newOfflineDatabaseFile = File(
        p.join(newDataDir.path, "${prefix}ente.offline_authenticator.db"),
      );
      if (await offlineDatabaseFile.exists() &&
          !await newOfflineDatabaseFile.exists()) {
        await offlineDatabaseFile.copy(newOfflineDatabaseFile.path);
      }

      sharedPrefs.setBool(migratedNamingChanges, true).ignore();
    } catch (e, st) {
      logger.warning("Migrating Database failed!", e, st);
      rethrow;
    }
  }
}
