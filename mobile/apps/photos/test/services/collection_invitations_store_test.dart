import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:photos/models/api/collection/user.dart';
import 'package:photos/models/collection/collection_invitation.dart';
import 'package:photos/services/collection_invitations_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late SharedPreferences preferences;
  late CollectionInvitationsStore store;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    preferences = await SharedPreferences.getInstance();
    store = CollectionInvitationsStore();
    await store.initialize(preferences, 1, decode: _decode);
  });

  tearDown(() => store.dispose());

  test(
    'only a complete unambiguous snapshot replaces cached requests',
    () async {
      await store.applySnapshot([_raw(1, 10), _raw(2, 20)]);
      expect(store.pending.map((item) => item.collectionID), [2, 1]);
      final saved = preferences.getString('collection_invitations_v1_1');

      expect(await store.applySnapshot(null), isNull);
      for (final invalid in <Object>[
        {'pending': <Object>[]},
        [_raw(3, 30), _raw(3, 30)],
      ]) {
        await expectLater(store.applySnapshot(invalid), throwsFormatException);
        expect(store.pending.map((item) => item.collectionID), [2, 1]);
        expect(preferences.getString('collection_invitations_v1_1'), saved);
      }

      await store.applySnapshot([_raw(2, 20)]);
      expect(store.pending.single.collectionID, 2);
      expect(await store.applySnapshot([]), isEmpty);
      expect(store.pending, isEmpty);
      expect(store.hasUnseen, isFalse);
    },
  );

  test(
    'bad previews are hidden without blocking snapshot reconciliation',
    () async {
      const error = FormatException(
        'private album title',
        'private invitation data',
      );
      await store.initialize(
        preferences,
        1,
        decode: (raw) => raw['collectionID'] == 3 ? throw error : _decode(raw),
      );
      final records = <LogRecord>[];
      final subscription = Logger(
        'CollectionInvitationsStore',
      ).onRecord.listen(records.add);
      addTearDown(subscription.cancel);
      await store.applySnapshot([_raw(1, 10), _raw(2, 20)]);
      await store.markSeen(store.pending);

      final loaded = await store.applySnapshot([
        _raw(1, 10),
        _raw(3, 30),
        _raw(4, 40),
      ]);
      expect(loaded!.map((item) => item.collectionID), [4, 1]);
      expect(store.hasUnseen, isTrue);
      final saved =
          jsonDecode(preferences.getString('collection_invitations_v1_1')!)
              as Map<String, dynamic>;
      expect((saved['pending'] as List).map((item) => item['collectionID']), [
        1,
        4,
      ]);
      expect(saved['seen'], ['1:10']);
      final record = records.single;
      expect(record.level, Level.SEVERE);
      expect(record.message, contains('invitation 3'));
      expect(record.error, isA<FormatException>());
      expect(record.stackTrace, isNotNull);
      expect(
        '${record.message} ${record.error}',
        allOf(isNot(contains(error.message)), isNot(contains(error.source))),
      );

      expect(await store.applySnapshot([_raw(3, 30)]), isEmpty);
      expect(store.pending, isEmpty);
      expect(store.hasUnseen, isFalse);
    },
  );

  test('cached malformed entries do not hide valid seen invitations', () async {
    await preferences.setString(
      'collection_invitations_v1_1',
      jsonEncode({
        'pending': [
          _raw(1, 10),
          {'collectionID': 2},
          null,
        ],
        'seen': ['1:10'],
      }),
    );

    await store.initialize(preferences, 1, decode: _decode);
    expect(store.pending.single.collectionID, 1);
    expect(store.hasUnseen, isFalse);
  });

  test(
    'seen state covers only loaded occurrences, not later invitations',
    () async {
      final loaded = (await store.applySnapshot([_raw(1, 10)]))!;
      expect(store.hasUnseen, isTrue);

      await store.applySnapshot([_raw(1, 10), _raw(2, 20)]);
      await store.markSeen(loaded);
      expect(store.hasUnseen, isTrue);

      await store.markSeen(store.pending);
      expect(store.hasUnseen, isFalse);
      expect(store.pending, hasLength(2));

      await store.applySnapshot([
        {
          ..._raw(1, 10),
          'encryptedName': 'renamed-ciphertext',
          'updationTime': 99,
        },
        _raw(2, 20),
      ]);
      expect(store.hasUnseen, isFalse);
      expect(store.pending.last.albumName, 'Decrypted renamed-ciphertext');

      await store.applySnapshot([_raw(1, 30), _raw(2, 20)]);
      expect(store.hasUnseen, isTrue);
      await store.markSeen(loaded);
      expect(store.hasUnseen, isTrue);

      await store.applySnapshot([_raw(2, 20)]);
      expect(store.hasUnseen, isFalse);
    },
  );

  test(
    'cache preserves encrypted previews and per-account seen state',
    () async {
      await store.applySnapshot([_raw(1, 10)]);
      await store.markSeen(store.pending);
      final saved = preferences.getString('collection_invitations_v1_1')!;
      final cache = jsonDecode(saved) as Map<String, dynamic>;
      expect((cache['pending'] as List).single, _raw(1, 10));
      expect(saved, isNot(contains('Decrypted')));
      expect(saved, isNot(contains('albumName')));

      final restarted = CollectionInvitationsStore();
      addTearDown(restarted.dispose);
      await restarted.initialize(preferences, 1, decode: _decode);
      expect(restarted.pending.single.albumName, 'Decrypted title-1');
      expect(restarted.hasUnseen, isFalse);

      await restarted.initialize(preferences, 2, decode: _decode);
      expect(restarted.pending, isEmpty);
      await restarted.applySnapshot([_raw(2, 20)]);
      expect(restarted.hasUnseen, isTrue);

      await restarted.initialize(preferences, 1, decode: _decode);
      expect(restarted.pending.single.collectionID, 1);
      expect(restarted.hasUnseen, isFalse);
      await restarted.clearAccount();
      expect(restarted.accountID, isNull);
      expect(restarted.pending, isEmpty);
      expect(preferences.getString('collection_invitations_v1_1'), isNull);

      await restarted.initialize(preferences, 2, decode: _decode);
      expect(restarted.pending.single.collectionID, 2);
      expect(restarted.hasUnseen, isTrue);
    },
  );

  test('successful mutation removes only returned accepted IDs', () async {
    final loaded = (await store.applySnapshot([_raw(1, 10), _raw(2, 20)]))!;
    await store.markSeen(loaded);
    await store.applySnapshot([_raw(1, 10), _raw(2, 20), _raw(3, 30)]);

    await store.removeAccepted([1, 2]);
    expect(store.pending.single.collectionID, 3);
    expect(store.hasUnseen, isTrue);

    final restarted = CollectionInvitationsStore();
    addTearDown(restarted.dispose);
    await restarted.initialize(preferences, 1, decode: _decode);
    expect(restarted.pending.single.collectionID, 3);
    expect(restarted.hasUnseen, isTrue);
  });

  test('logout cannot be undone by an in-flight snapshot write', () async {
    await store.applySnapshot([_raw(1, 10)]);
    final applying = store.applySnapshot([_raw(2, 20)]);
    final clearing = store.clearAccount();
    await applying;
    await clearing;
    expect(store.accountID, isNull);
    expect(store.pending, isEmpty);
    expect(store.hasUnseen, isFalse);

    await store.initialize(preferences, 1, decode: _decode);
    expect(store.pending, isEmpty);
  });

  test('late responses cannot change a newer account generation', () async {
    final oldGeneration = store.generation;
    await store.initialize(preferences, 2, decode: _decode);
    await store.applySnapshot([_raw(2, 20)]);
    await store.markSeen(store.pending);
    final saved = preferences.getString('collection_invitations_v1_2');

    expect(
      await store.applySnapshot([
        _raw(1, 10),
      ], expectedGeneration: oldGeneration),
      isNull,
    );
    await store.removeAccepted([2], expectedGeneration: oldGeneration);
    expect(store.pending.single.collectionID, 2);
    expect(store.hasUnseen, isFalse);
    expect(preferences.getString('collection_invitations_v1_2'), saved);

    final beforeReinitialization = store.generation;
    await store.initialize(preferences, 2, decode: _decode);
    expect(
      await store.applySnapshot([], expectedGeneration: beforeReinitialization),
      isNull,
    );
    expect(store.pending.single.collectionID, 2);
    expect(preferences.getString('collection_invitations_v1_2'), saved);
  });
}

Map<String, dynamic> _raw(int collectionID, int sharedAt) => {
  'collectionID': collectionID,
  'inviter': {'id': 7, 'email': 'alice@example.com'},
  'encryptedKey': 'wrapped-key-$collectionID',
  'encryptedName': 'title-$collectionID',
  'nameDecryptionNonce': 'nonce-$collectionID',
  'sharedAt': sharedAt,
};

CollectionInvitation _decode(Map<String, dynamic> raw) {
  if (raw['collectionID'] is! int ||
      raw['sharedAt'] is! int ||
      raw['encryptedName'] is! String ||
      raw['inviter'] is! Map) {
    throw const FormatException('Incomplete invitation');
  }
  return CollectionInvitation(
    collectionID: raw['collectionID'] as int,
    inviter: User.fromMap(Map<String, dynamic>.from(raw['inviter'] as Map)),
    albumName: 'Decrypted ${raw['encryptedName']}',
    sharedAt: raw['sharedAt'] as int,
  );
}
