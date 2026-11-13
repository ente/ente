import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import '../../test/services/sync/backup_preparation_test.dart';

Future<void> measurePreparation(PreparationFixture fixture) async {
  const cases = [
    (
      name: 'empty',
      folders: 0,
      active: 0,
      assets: 0,
      uploaded: 0,
      queued: 0,
      overlap: false,
    ),
    (
      name: 'one_mixed',
      folders: 1,
      active: 1,
      assets: 10000,
      uploaded: 4000,
      queued: 3000,
      overlap: false,
    ),
    (
      name: 'two_mixed',
      folders: 2,
      active: 2,
      assets: 10000,
      uploaded: 4000,
      queued: 3000,
      overlap: false,
    ),
    (
      name: 'typical_new',
      folders: 50,
      active: 50,
      assets: 10000,
      uploaded: 1000,
      queued: 0,
      overlap: false,
    ),
    (
      name: 'two_large',
      folders: 2,
      active: 2,
      assets: 100000,
      uploaded: 40000,
      queued: 30000,
      overlap: false,
    ),
    (
      name: 'many_backed',
      folders: 500,
      active: 500,
      assets: 10000,
      uploaded: 10000,
      queued: 0,
      overlap: false,
    ),
    (
      name: 'both_large',
      folders: 100,
      active: 100,
      assets: 100000,
      uploaded: 10000,
      queued: 0,
      overlap: false,
    ),
    (
      name: 'customer_scale',
      folders: 1903,
      active: 1903,
      assets: 37302,
      uploaded: 15000,
      queued: 22302,
      overlap: false,
    ),
    (
      name: 'retained',
      folders: 1903,
      active: 10,
      assets: 37302,
      uploaded: 15000,
      queued: 22302,
      overlap: false,
    ),
    (
      name: 'overlap',
      folders: 5,
      active: 5,
      assets: 10000,
      uploaded: 1000,
      queued: 0,
      overlap: true,
    ),
  ];
  var record = 0;
  for (final c in cases) {
    await fixture.reset();
    await fixture.raw.writeTransaction((tx) async {
      await tx.executeBatch(
        '''INSERT INTO device_collections
        (id,name,count,collection_id,upload_strategy,should_backup)
        VALUES (?,?,?,?,0,1)''',
        [
          for (var i = 0; i < c.folders; i++)
            [
              'folder-$i',
              'Folder $i',
              i < c.active
                  ? (c.assets ~/ c.active + (i < c.assets % c.active ? 1 : 0)) *
                        (c.overlap ? 2 : 1)
                  : 0,
              1000 + i,
            ],
        ],
      );
      await tx.executeBatch(
        'INSERT INTO device_files(id,path_id) VALUES (?,?)',
        [
          for (var i = 0; i < c.assets; i++) ...[
            ['${1000000000 + i}', 'folder-${i % c.active}'],
            if (c.overlap)
              ['${1000000000 + i}', 'folder-${(i + 1) % c.active}'],
          ],
        ],
      );
      await tx.executeBatch(
        '''INSERT INTO files
        (local_id,uploaded_file_id,owner_id,collection_id,title,file_type,creation_time,modification_time)
        VALUES (?,?,?,?,?,0,100,100)''',
        [
          for (var i = 0; i < c.assets; i++)
            [
              '${1000000000 + i}',
              i < c.uploaded ? 2000000000 + i : null,
              i < c.uploaded ? 42 : null,
              i < c.uploaded + c.queued ? 1000 + i % c.active : null,
              'fixture_$i.jpg',
            ],
        ],
      );
    });
    for (final pass in [
      'first',
      'subsequent',
      if (c.name == 'many_backed') 'after_discovery',
    ]) {
      if (pass == 'after_discovery') {
        await fixture.file('new_photo');
        await fixture.raw.execute(
          'INSERT INTO device_files(id,path_id) VALUES (?,?)',
          ['new_photo', 'folder-0'],
        );
        await fixture.raw.execute(
          "UPDATE device_collections SET count=count+1 WHERE id='folder-0'",
        );
      }
      final baselineRss = ProcessInfo.currentRss;
      var peakRss = baselineRss;
      final timer = Timer.periodic(const Duration(milliseconds: 10), (_) {
        peakRss = max(peakRss, ProcessInfo.currentRss);
      });
      late Map<String, Object?> result;
      try {
        result = await fixture.prepare();
      } finally {
        timer.cancel();
        peakRss = max(peakRss, ProcessInfo.currentRss);
      }
      expect(fixture.db.claimedReads, c.folders == 0 ? 0 : 1);
      final pending = await fixture.pendingIDs();
      expect(
        pending.length,
        c.assets - c.uploaded + (pass == 'after_discovery' ? 1 : 0),
      );
      expect(pending.toSet().length, pending.length);
      final shape = await fixture.raw.get(
        'SELECT COUNT(DISTINCT local_id) AS n FROM files',
      );
      expect(shape['n'], c.assets + (pass == 'after_discovery' ? 1 : 0));
      final encoded = jsonEncode({
        'case': c.name,
        'folders': c.folders,
        'populated': c.active,
        'assets': c.assets,
        'pass': pass,
        ...result,
        'baselineRssBytes': baselineRss,
        'peakSampledRssBytes': peakRss,
        'pending': pending.length,
        'correctness': 'passed',
      });
      final parts = (encoded.length / 650).ceil();
      for (var part = 0; part < parts; part++) {
        // ignore: avoid_print
        print(
          'SHARED_CHECKLIST_PART $record $part $parts ${encoded.substring(part * 650, min((part + 1) * 650, encoded.length))}',
        );
      }
      record++;
    }
  }
}
