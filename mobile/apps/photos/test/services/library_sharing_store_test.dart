import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photos/gateways/entity/models/type.dart';
import 'package:photos/models/collection/collection.dart';
import 'package:photos/models/local_entity_data.dart';
import 'package:photos/services/entity_service.dart';
import 'package:photos/services/library_sharing_store.dart';

void main() {
  test('merges remote changes after a version conflict', () async {
    final entityService = _ConflictEntityService();
    final store = LibrarySharingEntityStore(entityService);
    final base = (await store.read(1, 2))!;

    final unchangedService = _ConflictEntityService();
    final unchangedStore = LibrarySharingEntityStore(unchangedService);
    await unchangedStore.write(1, (await unchangedStore.read(1, 2))!);
    expect(unchangedService._writes, 2);

    final saved = await store.write(
      1,
      base.copyWith(unsharedBefore: {}, hidden: {3}),
    );
    expect(saved.enabled, isTrue);
    expect(saved.defaultRole, CollectionParticipantRole.admin);
    expect(saved.addedAutomatically, {4});
    expect(saved.unsharedBefore, {2});
    expect(saved.hidden, {3});
  });

  test('fails when remote sync fails', () async {
    final entityService = _ConflictEntityService()..syncResult = -1;

    await expectLater(
      LibrarySharingEntityStore(entityService).sync(),
      throwsStateError,
    );
  });
}

class _ConflictEntityService implements EntityService {
  _ConflictEntityService() : current = _entity(_base, 1);

  LocalEntityData current;
  int syncResult = 1;
  var _writes = 0;

  @override
  Future<LocalEntityData?> getEntity(EntityType type, String id) async =>
      current;

  @override
  Future<int> syncEntity(EntityType type) async {
    if (syncResult >= 0) {
      current = _entity(_remote, 2);
    }
    return syncResult;
  }

  @override
  Future<LocalEntityData> addOrUpdate(
    EntityType type,
    Map<String, dynamic> jsonMap, {
    String? id,
    bool addWithCustomID = false,
    int? expectedUpdatedAt,
  }) async {
    expect(id, 'ls_1_2');
    expect(expectedUpdatedAt, _writes == 0 ? 1 : 2);
    if (_writes++ == 0) {
      final options = RequestOptions(path: '/user-entity/entity');
      throw DioException(
        requestOptions: options,
        response: Response(requestOptions: options, statusCode: 409),
      );
    }
    current = _entity(LibrarySharingConfig.fromJson(jsonMap), 3);
    return current;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _base = LibrarySharingConfig(
  recipientUserID: 2,
  enabled: false,
  defaultRole: CollectionParticipantRole.viewer,
  unsharedBefore: {1},
);

const _remote = LibrarySharingConfig(
  recipientUserID: 2,
  enabled: true,
  defaultRole: CollectionParticipantRole.admin,
  addedAutomatically: {4},
  unsharedBefore: {1, 2},
);

LocalEntityData _entity(LibrarySharingConfig config, int updatedAt) =>
    LocalEntityData(
      id: 'ls_1_2',
      type: EntityType.libraryShare,
      data: jsonEncode(config.toJson()),
      ownerID: 1,
      updatedAt: updatedAt,
    );
