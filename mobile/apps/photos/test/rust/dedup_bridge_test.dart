import 'dart:convert';
import 'dart:io';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photos/src/rust/api/dedup_api.dart';
import 'package:photos/src/rust/frb_generated.dart';

import 'rust_test_helpers.dart';

void main() {
  final library = Platform.environment['ENTE_PHOTOS_FRB_LIBRARY'] ?? '';

  test(
    'finds and removes duplicates through the generated Dart bindings',
    () async {
      await EntePhotosRust.init(externalLibrary: ExternalLibrary.open(library));
      final requests = <(String, Map<String, dynamic>)>[];
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        final body = await utf8.decoder.bind(request).join();
        requests.add((
          request.uri.path,
          jsonDecode(body) as Map<String, dynamic>,
        ));
        request.response
          ..headers.contentType = ContentType.json
          ..write('{}');
        await request.response.close();
      });

      final files = [
        for (final (id, album) in [(21, 11), (21, 12), (22, 12)])
          DedupFile(
            id: id,
            collectionId: album,
            ownerId: 1,
            hash: 'test hash',
            size: BigInt.from(100),
          ),
      ];
      final groups = await findDuplicates(
        userId: 1,
        collections: [
          for (final id in [11, 12])
            DedupCollection(id: id, ownerId: 1, isHidden: false),
        ],
        files: files,
      );
      final group = groups.single;
      expect(group.itemSize, BigInt.from(100));
      expect(group.items.map((item) => item.fileIndex.toInt()), [0, 2]);
      expect(group.items.first.collectionIds.map((id) => id.toInt()), [11, 12]);

      final session = openTestSession(server.port);
      addTearDown(session.dispose);
      final events = await executeDuplicateRemoval(
        session: session,
        input: ExecuteDuplicateRemovalInput(
          groups: [
            [
              for (final item in group.items)
                Duplicate(
                  fileId: files[item.fileIndex.toInt()].id,
                  collectionIds: item.collectionIds,
                  caption: item.fileIndex == BigInt.two
                      ? 'Keep this copy'
                      : null,
                ),
            ],
          ],
          collections: [RemovalCollection(id: 11, key: Uint8List(32))],
          files: [
            for (final index in [0, 2])
              RemovalFile(
                id: files[index].id,
                collectionId: files[index].collectionId,
                key: Uint8List(32),
              ),
          ],
        ),
      ).toList();

      expect(events, [
        DuplicateRemovalEvent.progress(
          completed: BigInt.one,
          total: BigInt.two,
        ),
        DuplicateRemovalEvent.progress(
          completed: BigInt.two,
          total: BigInt.two,
        ),
        isA<DuplicateRemovalEvent_Completed>().having(
          (event) => event.trashIds.map((id) => id.toInt()),
          'trashed IDs',
          [21],
        ),
      ]);
      expect(requests.map((request) => request.$1), [
        '/collections/add-files',
        '/files/trash',
      ]);
      expect(requests.first.$2, {
        'collectionID': 11,
        'files': [
          {
            'id': 22,
            'encryptedKey': isA<String>(),
            'keyDecryptionNonce': isA<String>(),
          },
        ],
      });
      expect(requests.last.$2, {
        'items': [
          {'fileID': 21, 'collectionID': 11},
        ],
      });
    },
    skip: library.isEmpty
        ? 'Set ENTE_PHOTOS_FRB_LIBRARY to run against Rust'
        : false,
  );
}
