import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:logging/logging.dart';
import 'package:photos/gateways/entity/models/type.dart';
import 'package:photos/models/collection/collection.dart';
import 'package:photos/models/local_entity_data.dart';
import 'package:photos/services/entity_service.dart';

class LibrarySharingConfig {
  const LibrarySharingConfig({
    required this.recipientUserID,
    required this.enabled,
    required this.defaultRole,
    this.addedAutomatically = const {},
    this.unsharedBefore = const {},
    this.hidden = const {},
    this.updatedAt,
    this.base,
  });

  static const schemaVersion = 1;

  final int recipientUserID;
  final bool enabled;
  final CollectionParticipantRole defaultRole;
  final Set<int> addedAutomatically;
  final Set<int> unsharedBefore;
  final Set<int> hidden;
  final int? updatedAt;
  final LibrarySharingConfig? base;

  LibrarySharingConfig copyWith({
    bool? enabled,
    CollectionParticipantRole? defaultRole,
    Set<int>? addedAutomatically,
    Set<int>? unsharedBefore,
    Set<int>? hidden,
    int? updatedAt,
    LibrarySharingConfig? base,
  }) => LibrarySharingConfig(
    recipientUserID: recipientUserID,
    enabled: enabled ?? this.enabled,
    defaultRole: defaultRole ?? this.defaultRole,
    addedAutomatically: addedAutomatically ?? this.addedAutomatically,
    unsharedBefore: unsharedBefore ?? this.unsharedBefore,
    hidden: hidden ?? this.hidden,
    updatedAt: updatedAt ?? this.updatedAt,
    base: base ?? this.base,
  );

  LibrarySharingConfig _synced(int updatedAt) =>
      copyWith(updatedAt: updatedAt, base: this);

  Map<String, dynamic> toJson() => {
    'version': schemaVersion,
    'recipientUserID': recipientUserID,
    'enabled': enabled,
    'defaultRole': defaultRole.name,
    'addedAutomatically': addedAutomatically.toList()..sort(),
    'unsharedBefore': unsharedBefore.toList()..sort(),
    'hidden': hidden.toList()..sort(),
  };

  factory LibrarySharingConfig.fromJson(Map<String, dynamic> json) {
    if (json['version'] != schemaVersion) {
      throw const FormatException('Unsupported library sharing version');
    }
    final recipientUserID = json['recipientUserID'];
    if (recipientUserID is! int || recipientUserID <= 0) {
      throw const FormatException('Invalid library sharing recipient');
    }
    final role = CollectionParticipantRoleExtn.fromString(
      json['defaultRole'] as String?,
    );
    return LibrarySharingConfig(
      recipientUserID: recipientUserID,
      enabled: json['enabled'] as bool? ?? false,
      defaultRole: switch (role) {
        CollectionParticipantRole.viewer ||
        CollectionParticipantRole.collaborator ||
        CollectionParticipantRole.admin => role,
        _ => CollectionParticipantRole.viewer,
      },
      addedAutomatically: _intSet(json['addedAutomatically']),
      unsharedBefore: _intSet(json['unsharedBefore']),
      hidden: _intSet(json['hidden']),
    );
  }
}

class LibrarySharingEntityStore {
  LibrarySharingEntityStore(this._entityService);

  static const _type = EntityType.libraryShare;
  static const _writeAttempts = 2;

  final EntityService _entityService;
  final _logger = Logger('LibrarySharingEntityStore');

  Future<void> sync() async {
    if (await _entityService.syncEntity(_type) < 0) {
      throw StateError('Could not sync library sharing state');
    }
  }

  Future<LibrarySharingConfig?> read(
    int ownerUserID,
    int recipientUserID,
  ) async {
    final entity = await _entityService.getEntity(
      _type,
      _entityID(ownerUserID, recipientUserID),
    );
    return entity == null ? null : _decode(entity, ownerUserID);
  }

  Future<List<LibrarySharingConfig>> readAll(int ownerUserID) async {
    final configs = <LibrarySharingConfig>[];
    for (final entity in await _entityService.getEntities(_type)) {
      if (entity.ownerID != ownerUserID) {
        continue;
      }
      try {
        configs.add(_decode(entity, ownerUserID));
      } catch (error, stackTrace) {
        _logger.warning(
          'Ignoring invalid library sharing entity ${entity.id}',
          error,
          stackTrace,
        );
      }
    }
    return configs;
  }

  Future<LibrarySharingConfig> write(
    int ownerUserID,
    LibrarySharingConfig config,
  ) async {
    final id = _entityID(ownerUserID, config.recipientUserID);
    final base = config.base;
    var desired = config;
    var expectedUpdatedAt = config.updatedAt;

    for (var attempt = 0; attempt < _writeAttempts; attempt++) {
      try {
        final saved = await _entityService.addOrUpdate(
          _type,
          desired.toJson(),
          id: id,
          addWithCustomID: expectedUpdatedAt == null,
          expectedUpdatedAt: expectedUpdatedAt,
        );
        return desired._synced(saved.updatedAt);
      } on DioException catch (error) {
        if (error.response?.statusCode != 409 ||
            attempt == _writeAttempts - 1) {
          rethrow;
        }
        await sync();
        final current = await _entityService.getEntity(_type, id);
        if (current != null) {
          desired = _merge(base, desired, _decode(current, ownerUserID));
        }
        expectedUpdatedAt = current?.updatedAt;
      }
    }
    throw StateError('Could not save library sharing state');
  }

  LibrarySharingConfig _decode(LocalEntityData entity, int ownerUserID) {
    final config = LibrarySharingConfig.fromJson(
      Map<String, dynamic>.from(jsonDecode(entity.data) as Map),
    );
    if (entity.ownerID != ownerUserID ||
        config.recipientUserID == ownerUserID ||
        entity.id != _entityID(ownerUserID, config.recipientUserID)) {
      throw const FormatException(
        'Library sharing recipient does not match ID',
      );
    }
    return config._synced(entity.updatedAt);
  }

  LibrarySharingConfig _merge(
    LibrarySharingConfig? base,
    LibrarySharingConfig desired,
    LibrarySharingConfig remote,
  ) {
    final baseAddedAutomatically = base?.addedAutomatically ?? const <int>{};
    final baseUnsharedBefore = base?.unsharedBefore ?? const <int>{};
    final baseHidden = base?.hidden ?? const <int>{};
    return LibrarySharingConfig(
      recipientUserID: desired.recipientUserID,
      enabled: base == null || desired.enabled != base.enabled
          ? desired.enabled
          : remote.enabled,
      defaultRole: base == null || desired.defaultRole != base.defaultRole
          ? desired.defaultRole
          : remote.defaultRole,
      addedAutomatically: _mergeSet(
        baseAddedAutomatically,
        desired.addedAutomatically,
        remote.addedAutomatically,
      ),
      unsharedBefore: _mergeSet(
        baseUnsharedBefore,
        desired.unsharedBefore,
        remote.unsharedBefore,
      ),
      hidden: _mergeSet(baseHidden, desired.hidden, remote.hidden),
    );
  }

  String _entityID(int ownerUserID, int recipientUserID) =>
      'ls_${ownerUserID}_$recipientUserID';
}

Set<int> _mergeSet(Set<int> base, Set<int> desired, Set<int> remote) =>
    {...remote, ...desired.difference(base)}
      ..removeAll(base.difference(desired));

Set<int> _intSet(dynamic value) =>
    value is List ? value.whereType<int>().toSet() : <int>{};
