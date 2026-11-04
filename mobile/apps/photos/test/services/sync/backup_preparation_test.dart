import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:photos/core/configuration.dart';
import 'package:photos/db/common/conflict_algo.dart';
import 'package:photos/db/files_db.dart';
import 'package:photos/models/collection/collection.dart';
import 'package:photos/models/file/file.dart';
import 'package:photos/module/upload/service/file_uploader.dart';
import 'package:photos/service_locator.dart';
import 'package:photos/services/collections_service.dart';
import 'package:photos/services/sync/remote_sync_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite_async/sqlite_async.dart';

void main() => registerPreparationTests();

void registerPreparationTests({
  void Function(String, Future<void> Function())? registerTest,
  void Function(PreparationFixture)? onFixtureCreated,
}) {
  final runTest =
      registerTest ??
      (String name, Future<void> Function() body) {
        test(name, body);
      };
  TestWidgetsFlutterBinding.ensureInitialized();
  late PreparationFixture fixture;
  setUpAll(() async {
    fixture = await PreparationFixture.create();
    onFixtureCreated?.call(fixture);
  });
  setUp(() async => fixture.reset());
  tearDownAll(() async => fixture.close());

  runTest(
    'shares claims across overlapping folders and starts fresh next pass',
    () async {
      await fixture.file('local');
      await fixture.folder('first', 1000, ['local']);
      await fixture.folder('second', 1001, ['local']);
      await fixture.prepare();
      expect(fixture.db.claimedReads, 1);
      expect(fixture.db.mappingCalls, 1);
      expect(await fixture.pendingIDs(), ['local']);

      await fixture.file('new');
      await fixture.raw.executeBatch(
        'INSERT INTO device_files(id,path_id) VALUES (?,?)',
        [
          ['new', 'first'],
          ['new', 'second'],
        ],
      );
      await fixture.prepare();
      expect(fixture.db.claimedReads, 1);
      expect(fixture.db.mappingCalls, 1);
      expect(await fixture.pendingIDs(), ['local', 'new']);
    },
  );

  runTest(
    'single-folder preparation does not request mapping return rows',
    () async {
      await fixture.file('local');
      await fixture.folder('only', 1000, ['local']);
      await fixture.prepare();
      expect(fixture.db.claimedReads, 1);
      expect(fixture.db.trackedMappings, 0);
      expect(await fixture.pendingIDs(), ['local']);
    },
  );

  runTest(
    'foreign mappings do not prematurely claim an owned backup',
    () async {
      await fixture.file(
        'foreign_mapped',
        owner: 99,
        uploaded: 456,
        collection: 9000,
      );
      await fixture.file('foreign_unmapped', owner: 99, uploaded: 457);
      await fixture.file('current', owner: 42, uploaded: 458);
      await fixture.file('local');
      await fixture.file('second_only');
      final shared = ['foreign_mapped', 'foreign_unmapped', 'current', 'local'];
      await fixture.folder('second', 1001, [...shared, 'second_only']);
      await fixture.folder('first', 1000, shared);
      await fixture.prepare();
      expect(fixture.db.claimedReads, 1);
      expect(fixture.db.claimedRows, 0);
      expect(await fixture.pendingIDs(), [
        'foreign_mapped',
        'foreign_unmapped',
        'local',
        'second_only',
      ]);
      final row = await fixture.raw.get('''SELECT collection_id FROM files
      WHERE local_id = 'foreign_unmapped' AND owner_id IS NULL''');
      expect(row['collection_id'], 1001);
      expect(
        (await fixture.raw.get(
          'SELECT COUNT(*) AS n FROM files WHERE owner_id=99',
        ))['n'],
        2,
      );
    },
  );

  runTest(
    'Always mappings and copies update claims without changing only-new filtering',
    () async {
      await backupPreferenceService.setOnlyNewSinceEpoch(100);
      await fixture.file('old', created: 99);
      await fixture.file('new', created: 100);
      await fixture.file(
        'uploaded',
        owner: 42,
        uploaded: 456,
        collection: 9000,
      );
      await fixture.file('always_new');
      await fixture.folder('first', 1000, ['old', 'new']);
      await fixture.folder('always', 1001, [
        'uploaded',
        'new',
        'always_new',
      ], strategy: 1);
      await fixture.folder('last', 1002, [
        'old',
        'new',
        'uploaded',
        'always_new',
      ]);
      await fixture.prepare();
      expect(fixture.db.claimedReads, 1);
      expect(fixture.db.mappingCalls, 2);
      expect(await fixture.pendingIDs(), [
        'always_new',
        'new',
        'new',
        'uploaded',
      ]);
      expect(
        (await fixture.raw.get(
          "SELECT collection_id FROM files WHERE local_id='old'",
        ))['collection_id'],
        isNull,
      );
    },
  );

  for (final failsAfterDelete in [false, true]) {
    runTest(
      'refreshes claims after ${failsAfterDelete ? 'partially failed' : 'successful'} stale cleanup',
      () async {
        await fixture.file('edge', owner: 42, uploaded: 456);
        await fixture.file('edge', collection: 9000);
        await fixture.file(
          'backed_up',
          owner: 42,
          uploaded: 457,
          collection: 1001,
        );
        await fixture.folder('second', 1001, ['edge', 'backed_up']);
        await fixture.folder('first', 1000, ['edge']);
        fixture.db.failCleanupOnce = failsAfterDelete;
        await fixture.prepare();
        expect(fixture.db.claimedReads, 2);
        expect(await fixture.pendingIDs(), isEmpty);
        final row = await fixture.raw.get(
          "SELECT collection_id FROM files WHERE local_id='edge'",
        );
        expect(row['collection_id'], 1001);
      },
    );
  }

  runTest(
    'missing file rows are not claimed before a later folder can import them',
    () async {
      await fixture.file('second_only');
      await fixture.folder('second', 1001, ['late', 'second_only']);
      await fixture.folder('first', 1000, ['late']);
      fixture.db.afterLocalRead = (_) async {
        fixture.db.afterLocalRead = null;
        await fixture.file('late');
      };
      await fixture.prepare();
      expect(fixture.db.claimedReads, 1);
      expect(await fixture.pendingIDs(), ['late', 'second_only']);
      expect(
        (await fixture.raw.get(
          "SELECT collection_id FROM files WHERE local_id='late'",
        ))['collection_id'],
        1001,
      );
    },
  );

  runTest(
    'an intervening owned mapping is not cloned from a stale checklist',
    () async {
      await fixture.file('raced');
      // Keep this row mapped so it reaches the clone filter before being queued.
      await fixture.file(
        'unaffected',
        owner: 99,
        uploaded: 457,
        collection: 9001,
      );
      await fixture.file(
        'backed_up',
        owner: 42,
        uploaded: 458,
        collection: 9002,
      );
      await fixture.folder('third', 1002, ['raced', 'unaffected', 'backed_up']);
      await fixture.folder('empty', 1000, []);
      await fixture.folder('second', 1001, ['raced', 'unaffected']);
      fixture.db.beforeMapping = (_, _) async {
        fixture.db.beforeMapping = null;
        await fixture.raw.execute(
          "UPDATE files SET collection_id=9000 WHERE local_id='raced'",
        );
      };
      await fixture.prepare();
      expect(fixture.db.claimedReads, 1);
      expect(fixture.db.mappingCalls, 1);
      expect(await fixture.pendingIDs(), ['raced', 'unaffected']);
      expect(
        (await fixture.raw.get(
          "SELECT collection_id FROM files WHERE local_id='raced'",
        ))['collection_id'],
        9000,
      );
      expect(
        (await fixture.raw.get(
          "SELECT collection_id FROM files WHERE local_id='unaffected' AND owner_id IS NULL",
        ))['collection_id'],
        1001,
      );
    },
  );

  runTest(
    'missing collections do not claim files and disabled folders stay unmapped',
    () async {
      await fixture.file('local');
      await fixture.file('disabled');
      await fixture.file('second_only');
      await fixture.folder('second', 1001, ['local', 'second_only']);
      await fixture.folder('missing', 1000, ['local']);
      await fixture.folder('disabled', 1002, ['disabled'], selected: false);
      fixture.collections.missing.add(1000);
      await fixture.prepare();
      expect(fixture.db.claimedReads, 1);
      expect(await fixture.pendingIDs(), ['local', 'second_only']);
      expect(
        (await fixture.raw.get(
          "SELECT collection_id FROM files WHERE local_id='disabled'",
        ))['collection_id'],
        isNull,
      );
    },
  );

  runTest(
    'retained empty records do not repeat the account-wide read',
    () async {
      await fixture.file(
        'uploaded',
        owner: 42,
        uploaded: 456,
        collection: 9000,
      );
      for (var i = 0; i < 100; i++) {
        await fixture.folder(
          'folder-$i',
          1000 + i,
          i == 99 ? ['uploaded'] : [],
        );
      }
      await fixture.prepare();
      expect(fixture.db.claimedReads, 1);
      expect(await fixture.pendingIDs(), isEmpty);
    },
  );
}

class PreparationFixture {
  PreparationFixture._(
    this.directory,
    this.previousPaths,
    this.previousPrint,
    this.raw,
  );
  final Directory directory;
  final PathProviderPlatform previousPaths;
  final DebugPrintCallback previousPrint;
  final SqliteDatabase raw;
  final db = PreparationDatabase();
  final collections = _Collections();
  late RemoteSyncService service;

  static Future<PreparationFixture> create() async {
    final directory = await Directory.systemTemp.createTemp(
      'backup_preparation_',
    );
    final previousPaths = PathProviderPlatform.instance;
    final previousPrint = debugPrint;
    PathProviderPlatform.instance = _Paths(directory.path);
    debugPrint = (String? message, {int? wrapWidth}) {};
    // FileUploader's normal constructor requires an initialized network client.
    FileUploader.instance = _Uploader();
    SharedPreferences.setMockInitialValues({
      'has_selected_all_folders_for_backup': true,
    });
    final prefs = await SharedPreferences.getInstance();
    ServiceLocator.instance.init(
      prefs,
      Dio(),
      Dio(),
      Dio(),
      PackageInfo(
        appName: 'test',
        packageName: 'test',
        version: '1',
        buildNumber: '1',
      ),
    );
    final raw = await FilesDB.instance.sqliteAsyncDB;
    return PreparationFixture._(directory, previousPaths, previousPrint, raw);
  }

  Future<void> reset() async {
    for (final table in ['files', 'device_files', 'device_collections']) {
      await raw.execute('DELETE FROM $table');
    }
    await backupPreferenceService.clearOnlyNewSinceEpoch();
    db.beforeMapping = null;
    db.afterLocalRead = null;
    db.failCleanupOnce = false;
    collections.missing.clear();
    service = RemoteSyncService.forTesting(
      filesDB: db,
      configuration: _Configuration(),
      collectionsService: collections,
    );
  }

  Future<Map<String, Object?>> prepare() async {
    db.claimedReads = 0;
    db.claimedRows = 0;
    db.mappingCalls = 0;
    db.trackedMappings = 0;
    db.claimedQueryMs = 0;
    final watch = Stopwatch()..start();
    await service.syncDeviceCollectionFilesForUpload();
    return {
      'elapsedMs': watch.elapsedMicroseconds / 1000,
      'claimedReads': db.claimedReads,
      'claimedRows': db.claimedRows,
      'claimedQueryMs': db.claimedQueryMs,
      'mappingCalls': db.mappingCalls,
      'trackedMappings': db.trackedMappings,
    };
  }

  Future<void> file(
    String id, {
    int? owner,
    int? uploaded,
    int? collection,
    int created = 100,
  }) => raw.execute(
    '''INSERT INTO files
    (local_id,owner_id,uploaded_file_id,collection_id,title,file_type,creation_time,modification_time)
    VALUES (?,?,?,?,?,0,?,100)''',
    [id, owner, uploaded, collection, '$id.jpg', created],
  );

  Future<void> folder(
    String id,
    int collection,
    List<String> ids, {
    int strategy = 0,
    bool selected = true,
  }) async {
    await raw.execute(
      '''INSERT INTO device_collections
      (id,name,count,collection_id,upload_strategy,should_backup) VALUES (?,?,?,?,?,?)''',
      [id, id, ids.length, collection, strategy, selected ? 1 : 0],
    );
    if (ids.isNotEmpty) {
      await raw.executeBatch(
        'INSERT INTO device_files (id,path_id) VALUES (?,?)',
        [
          for (final localID in ids) [localID, id],
        ],
      );
    }
  }

  Future<List<String>> pendingIDs() async {
    final rows = await raw.getAll(
      '''SELECT local_id FROM files WHERE collection_id IS NOT NULL AND collection_id !=-1
      AND (uploaded_file_id IS NULL OR uploaded_file_id=-1) AND (owner_id IS NULL OR owner_id=42) ORDER BY local_id''',
    );
    return rows.map((r) => r['local_id'] as String).toList();
  }

  Future<void> close() async {
    await raw.close();
    PathProviderPlatform.instance = previousPaths;
    debugPrint = previousPrint;
    await directory.delete(recursive: true);
  }
}

class PreparationDatabase extends Fake implements FilesDB {
  final FilesDB real = FilesDB.instance;
  double claimedQueryMs = 0;
  int claimedReads = 0;
  int claimedRows = 0;
  int mappingCalls = 0;
  int trackedMappings = 0;
  bool failCleanupOnce = false;
  Future<void> Function(int, Set<String>)? beforeMapping;
  Future<void> Function(List<String>)? afterLocalRead;
  @override
  Future<SqliteDatabase> get sqliteAsyncDB => real.sqliteAsyncDB;
  @override
  Future<Set<String>> getLocalIDsMarkedForOrAlreadyUploaded(int ownerID) async {
    claimedReads++;
    final watch = Stopwatch()..start();
    final result = await real.getLocalIDsMarkedForOrAlreadyUploaded(ownerID);
    claimedQueryMs += watch.elapsedMicroseconds / 1000;
    claimedRows += result.length;
    return result;
  }

  @override
  Future<int> removeQueuedLocalFiles(Set<String> ids, int ownerID) async {
    final result = await real.removeQueuedLocalFiles(ids, ownerID);
    if (failCleanupOnce) {
      failCleanupOnce = false;
      throw StateError('cleanup failed after deletion');
    }
    return result;
  }

  @override
  Future<Set<String>> setCollectionIDForUnMappedLocalFiles(
    int id,
    Set<String> ids, {
    int? trackClaimsForOwner,
  }) async {
    mappingCalls++;
    if (trackClaimsForOwner != null) trackedMappings++;
    await beforeMapping?.call(id, ids);
    return real.setCollectionIDForUnMappedLocalFiles(
      id,
      ids,
      trackClaimsForOwner: trackClaimsForOwner,
    );
  }

  @override
  Future<Set<String>> getLocalFileIDsForCollection(int id) =>
      real.getLocalFileIDsForCollection(id);
  @override
  Future<Set<String>> getAllLocalIDsNewerThan(int time) =>
      real.getAllLocalIDsNewerThan(time);
  @override
  Future<List<EnteFile>> getLocalFiles(
    List<String> ids, {
    bool dedupeByLocalID = false,
  }) async {
    final result = await real.getLocalFiles(
      ids,
      dedupeByLocalID: dedupeByLocalID,
    );
    await afterLocalRead?.call(ids);
    return result;
  }

  @override
  Future<void> insertMultiple(
    List<EnteFile> files, {
    SqliteAsyncConflictAlgorithm conflictAlgorithm =
        SqliteAsyncConflictAlgorithm.replace,
  }) => real.insertMultiple(files, conflictAlgorithm: conflictAlgorithm);
}

class _Configuration extends Fake implements Configuration {
  @override
  int? getUserID() => 42;
}

class _Uploader extends Fake implements FileUploader {}

class _Collections extends Fake implements CollectionsService {
  final missing = <int>{};
  @override
  Collection? getCollectionByID(int id) =>
      missing.contains(id) ? null : _Collection(id);
  @override
  Future<Collection> fetchCollectionByID(int id) async => _Collection(id);
}

class _Collection extends Fake implements Collection {
  _Collection(this.id);
  @override
  final int id;
  @override
  bool get isDeleted => false;
}

class _Paths extends PathProviderPlatform {
  _Paths(this.path);
  final String path;
  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}
