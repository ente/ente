import 'dart:async';

import 'package:ente_pure_utils/ente_pure_utils.dart';
import 'package:logging/logging.dart';
import 'package:photos/core/configuration.dart';
import 'package:photos/core/errors.dart';
import 'package:photos/core/event_bus.dart';
import 'package:photos/events/collection_updated_event.dart';
import 'package:photos/events/user_details_changed_event.dart';
import 'package:photos/gateways/collections/models/collection_share.dart';
import 'package:photos/models/collection/collection.dart';
import 'package:photos/models/library_sharing/library_sharing_recipient.dart';
import 'package:photos/models/metadata/collection_magic.dart';
import 'package:photos/models/metadata/common_keys.dart';
import 'package:photos/models/user_details.dart';
import 'package:photos/services/account/user_service.dart';
import 'package:photos/services/collections_service.dart';
import 'package:photos/services/library_sharing_store.dart';
import 'package:photos/utils/contact_string_util.dart';
import 'package:synchronized/synchronized.dart';

const librarySharingRoles = [
  CollectionParticipantRole.viewer,
  CollectionParticipantRole.collaborator,
  CollectionParticipantRole.admin,
];

const _bulkShareLimit = 100;
const _reconcileEventSources = {
  'collections_updated',
  'createCollection',
  'collection_visibility_changed',
};

typedef EnableAutomaticSharingResult = ({
  Set<int> failedIDs,
  Set<int> previouslyUnsharedIDs,
});

CollectionParticipantRole? librarySharingRoleFor(
  Collection collection,
  int userID,
) {
  for (final sharee in collection.sharees) {
    if (sharee.id == userID) {
      final role = CollectionParticipantRoleExtn.fromString(sharee.role);
      return librarySharingRoles.contains(role) ? role : null;
    }
  }
  return null;
}

CollectionParticipantRole normalizeLibrarySharingRole(
  Collection collection,
  CollectionParticipantRole role,
) => collection.type == CollectionType.uncategorized
    ? CollectionParticipantRole.viewer
    : role;

abstract interface class LibrarySharingRepository {
  Future<List<Collection>> getEligibleAlbums();

  Future<Set<int>> shareAlbums({
    required LibrarySharingRecipient recipient,
    required Map<int, CollectionParticipantRole> roles,
  });

  Future<Set<int>> unshareAlbums({
    required int recipientUserID,
    required List<int> collectionIDs,
  });

  Future<bool> isAutomaticSharingEnabled(int recipientUserID);

  Future<EnableAutomaticSharingResult> enableAutomaticSharing({
    required LibrarySharingRecipient recipient,
    required CollectionParticipantRole role,
  });

  Future<void> disableAutomaticSharing(int recipientUserID);
}

class LibrarySharingService implements LibrarySharingRepository {
  LibrarySharingService({
    CollectionsService? collectionsService,
    UserService? userService,
    Configuration? configuration,
    required LibrarySharingEntityStore store,
  }) : _collectionsService = collectionsService ?? CollectionsService.instance,
       _userService = userService ?? UserService.instance,
       _configuration = configuration ?? Configuration.instance,
       _store = store;

  final CollectionsService _collectionsService;
  final UserService _userService;
  final Configuration _configuration;
  final LibrarySharingEntityStore _store;
  final _logger = Logger('LibrarySharingService');
  final _operationLock = Lock();

  StreamSubscription<CollectionUpdatedEvent>? _collectionSubscription;
  StreamSubscription<UserDetailsChangedEvent>? _userDetailsSubscription;
  bool _isReconciling = false;
  bool _reconcileAgain = false;

  Future<void> init() async {
    await _collectionSubscription?.cancel();
    await _userDetailsSubscription?.cancel();
    _collectionSubscription = Bus.instance
        .on<CollectionUpdatedEvent>()
        .where((event) => _reconcileEventSources.contains(event.source))
        .listen((_) => reconcile().ignore());
    _userDetailsSubscription = Bus.instance
        .on<UserDetailsChangedEvent>()
        .listen((_) => reconcile().ignore());
    await reconcile();
  }

  @override
  Future<List<Collection>> getEligibleAlbums() async {
    final collections = _eligibleAlbums().toList();
    return [
      ...await _collectionsService.orderCollectionsForAlbums(
        collections.where(
          (collection) => collection.type != CollectionType.uncategorized,
        ),
      ),
      ...collections.where(
        (collection) => collection.type == CollectionType.uncategorized,
      ),
    ];
  }

  @override
  Future<Set<int>> shareAlbums({
    required LibrarySharingRecipient recipient,
    required Map<int, CollectionParticipantRole> roles,
  }) => _operationLock.synchronized(() async {
    final ownerUserID = _currentOwnerUserID();
    await _store.sync();
    final publicKey = await _requirePublicKey(recipient.email);
    final statuses = await _shareInBatches(
      ownerUserID: ownerUserID,
      recipientUserID: recipient.userID,
      recipientEmail: recipient.email,
      publicKey: publicKey,
      roles: roles,
      source: CollectionShareSource.manual,
    );
    final succeededIDs = statuses.entries
        .where((entry) => _isShareSuccess(entry.value))
        .map((entry) => entry.key)
        .toSet();
    final config = await _store.read(ownerUserID, recipient.userID);
    if (config != null && succeededIDs.isNotEmpty) {
      await _writeConfig(
        ownerUserID,
        config.copyWith(
          unsharedBefore: config.unsharedBefore.difference(succeededIDs),
          hidden: config.hidden.difference(succeededIDs),
        ),
      );
    }
    return roles.keys.toSet().difference(succeededIDs);
  });

  @override
  Future<Set<int>> unshareAlbums({
    required int recipientUserID,
    required List<int> collectionIDs,
  }) => _operationLock.synchronized(() async {
    final ownerUserID = _currentOwnerUserID();
    await _store.sync();
    final statuses = await _unshareInBatches(
      ownerUserID: ownerUserID,
      recipientUserID: recipientUserID,
      collectionIDs: collectionIDs,
      source: CollectionShareSource.manual,
    );
    final succeededIDs = statuses.entries
        .where((entry) => _isUnshareSuccess(entry.value))
        .map((entry) => entry.key)
        .toSet();
    final config = await _store.read(ownerUserID, recipientUserID);
    if (config != null && succeededIDs.isNotEmpty) {
      await _writeConfig(
        ownerUserID,
        config.copyWith(
          addedAutomatically: config.addedAutomatically.difference(
            succeededIDs,
          ),
          unsharedBefore: {...config.unsharedBefore, ...succeededIDs},
        ),
      );
    }
    return collectionIDs.toSet().difference(succeededIDs);
  });

  Future<void> unshareAlbumFromAll(Collection collection) async {
    final recipientUserIDs = collection.sharees
        .map((sharee) => sharee.id)
        .toList();
    for (final recipientUserID in recipientUserIDs) {
      final failedIDs = await unshareAlbums(
        recipientUserID: recipientUserID,
        collectionIDs: [collection.id],
      );
      if (failedIDs.isNotEmpty) {
        throw StateError('Could not unshare collection ${collection.id}');
      }
    }
    final updated = _collectionsService.getCollectionByID(collection.id);
    if (updated == null) {
      throw StateError('Collection ${collection.id} is not cached');
    }
    if (!identical(updated, collection)) {
      collection.updateSharees(updated.sharees);
    }
  }

  @override
  Future<bool> isAutomaticSharingEnabled(int recipientUserID) async {
    final ownerUserID = _configuration.getUserID();
    if (ownerUserID == null) {
      return false;
    }
    await _store.sync();
    return (await _store.read(ownerUserID, recipientUserID))?.enabled ?? false;
  }

  @override
  Future<EnableAutomaticSharingResult> enableAutomaticSharing({
    required LibrarySharingRecipient recipient,
    required CollectionParticipantRole role,
  }) async {
    final result = await _operationLock.synchronized(
      () => _enableAutomaticSharing(recipient, role),
    );
    if (result.failedIDs.isEmpty) {
      await reconcile();
    }
    return result;
  }

  Future<EnableAutomaticSharingResult> _enableAutomaticSharing(
    LibrarySharingRecipient recipient,
    CollectionParticipantRole role,
  ) async {
    if (!librarySharingRoles.contains(role)) {
      throw ArgumentError.value(role, 'role');
    }
    final ownerUserID = _currentOwnerUserID();
    await _store.sync();
    final publicKey = await _requirePublicKey(recipient.email);
    final existing = await _store.read(ownerUserID, recipient.userID);
    var config =
        (existing ??
                LibrarySharingConfig(
                  recipientUserID: recipient.userID,
                  enabled: false,
                  defaultRole: role,
                ))
            .copyWith(defaultRole: role);
    final collections = _automaticallyShareableOwnedCollections(
      ownerUserID,
    ).toList();
    config = _observeCollections(config, collections);
    config = await _writeConfig(ownerUserID, config);

    final roles = _automaticShareRoles(collections, config);
    final statuses = roles.isEmpty
        ? <int, CollectionShareStatus>{}
        : await _shareInBatches(
            ownerUserID: ownerUserID,
            recipientUserID: recipient.userID,
            recipientEmail: recipient.email,
            publicKey: publicKey,
            roles: roles,
            source: CollectionShareSource.automatic,
          );
    config = _applyAutomaticShareResults(config, statuses);
    final failedIDs = roles.keys
        .where((id) => !_isAutomaticShareSuccess(statuses[id]))
        .toSet();
    await _writeConfig(
      ownerUserID,
      config.copyWith(enabled: failedIDs.isEmpty),
    );
    final previouslyUnsharedIDs = collections
        .where(
          (collection) =>
              config.unsharedBefore.contains(collection.id) &&
              !config.hidden.contains(collection.id) &&
              librarySharingRoleFor(collection, recipient.userID) == null,
        )
        .map((collection) => collection.id)
        .toSet();
    return (failedIDs: failedIDs, previouslyUnsharedIDs: previouslyUnsharedIDs);
  }

  @override
  Future<void> disableAutomaticSharing(int recipientUserID) =>
      _operationLock.synchronized(() async {
        final ownerUserID = _currentOwnerUserID();
        await _store.sync();
        final config = await _store.read(ownerUserID, recipientUserID);
        if (config != null && config.enabled) {
          await _writeConfig(ownerUserID, config.copyWith(enabled: false));
        }
      });

  Future<void> reconcile() async {
    if (_isReconciling) {
      _reconcileAgain = true;
      return;
    }
    _isReconciling = true;
    try {
      do {
        _reconcileAgain = false;
        await _reconcileAll();
      } while (_reconcileAgain);
    } finally {
      _isReconciling = false;
    }
  }

  Future<void> _reconcileAll() async {
    final ownerUserID = _configuration.getUserID();
    if (ownerUserID == null) {
      return;
    }
    try {
      await _store.sync();
    } catch (error, stackTrace) {
      _logger.warning(
        'Could not sync library sharing state',
        error,
        stackTrace,
      );
      return;
    }
    final configs = await _store.readAll(ownerUserID);
    for (final config in configs.where((config) => config.enabled)) {
      try {
        await _operationLock.synchronized(() async {
          final latest = await _store.read(ownerUserID, config.recipientUserID);
          if (latest == null || !latest.enabled) {
            return;
          }
          final activeFamilyMemberUserIDs = _activeFamilyMemberUserIDs();
          if (activeFamilyMemberUserIDs != null &&
              !activeFamilyMemberUserIDs.contains(latest.recipientUserID)) {
            await _writeConfig(ownerUserID, latest.copyWith(enabled: false));
          } else {
            try {
              await _reconcileConfig(ownerUserID, latest);
            } on AutomaticShareRecipientNotEligibleError {
              await _refreshFamilyAndHandleIneligibleRecipient(
                ownerUserID,
                latest,
              );
            }
          }
        });
      } catch (error, stackTrace) {
        _logger.warning(
          'Could not reconcile library sharing for ${config.recipientUserID}',
          error,
          stackTrace,
        );
      }
    }
  }

  Future<void> _reconcileConfig(
    int ownerUserID,
    LibrarySharingConfig config,
  ) async {
    final collections = _automaticallyShareableOwnedCollections(
      ownerUserID,
    ).toList();
    config = _observeCollections(config, collections);
    config = await _writeConfig(ownerUserID, config);
    if (!config.enabled) {
      return;
    }

    final roles = _automaticShareRoles(collections, config);
    if (roles.isEmpty) {
      return;
    }
    final recipientEmail = _recipientEmail(config.recipientUserID);
    final statuses = await _shareInBatches(
      ownerUserID: ownerUserID,
      recipientUserID: config.recipientUserID,
      recipientEmail: recipientEmail,
      publicKey: await _requirePublicKey(recipientEmail),
      roles: roles,
      source: CollectionShareSource.automatic,
    );
    config = _applyAutomaticShareResults(config, statuses);
    await _writeConfig(ownerUserID, config);
  }

  LibrarySharingConfig _observeCollections(
    LibrarySharingConfig config,
    List<Collection> collections,
  ) {
    final collectionIDs = collections
        .map((collection) => collection.id)
        .toSet();
    return config.copyWith(
      addedAutomatically: config.addedAutomatically.intersection(collectionIDs),
      unsharedBefore: config.unsharedBefore.intersection(collectionIDs),
      hidden: {
        ...config.hidden.intersection(collectionIDs),
        ...collections
            .where(_isHiddenOwnedAlbum)
            .map((collection) => collection.id),
      },
    );
  }

  Map<int, CollectionParticipantRole> _automaticShareRoles(
    List<Collection> collections,
    LibrarySharingConfig config,
  ) => {
    for (final collection in collections)
      if (!config.hidden.contains(collection.id) &&
          !config.unsharedBefore.contains(collection.id) &&
          librarySharingRoleFor(collection, config.recipientUserID) == null)
        collection.id: normalizeLibrarySharingRole(
          collection,
          config.defaultRole,
        ),
  };

  LibrarySharingConfig _applyAutomaticShareResults(
    LibrarySharingConfig config,
    Map<int, CollectionShareStatus> statuses,
  ) {
    final addedAutomatically = {...config.addedAutomatically};
    final unsharedBefore = {...config.unsharedBefore};
    for (final entry in statuses.entries) {
      if (entry.value == CollectionShareStatus.shared) {
        addedAutomatically.add(entry.key);
      } else if (entry.value == CollectionShareStatus.blockedPreviousRemoval) {
        addedAutomatically.remove(entry.key);
        unsharedBefore.add(entry.key);
      }
    }
    return config.copyWith(
      addedAutomatically: addedAutomatically,
      unsharedBefore: unsharedBefore,
    );
  }

  Future<Map<int, CollectionShareStatus>> _shareInBatches({
    required int ownerUserID,
    required int recipientUserID,
    required String recipientEmail,
    required String publicKey,
    required Map<int, CollectionParticipantRole> roles,
    required CollectionShareSource source,
  }) async {
    final statuses = {
      for (final id in roles.keys) id: CollectionShareStatus.failed,
    };
    for (final batch in roles.entries.toList().chunks(_bulkShareLimit)) {
      _ensureCurrentOwner(ownerUserID);
      try {
        statuses.addAll(
          await _collectionsService.shareBulk(
            recipientUserID: recipientUserID,
            recipientEmail: recipientEmail,
            publicKey: publicKey,
            roles: Map.fromEntries(batch),
            source: source,
          ),
        );
      } on RecipientIdentityMismatchError {
        rethrow;
      } on AutomaticShareRecipientNotEligibleError {
        rethrow;
      } catch (error, stackTrace) {
        _logger.warning('Bulk library share failed', error, stackTrace);
      }
    }
    return statuses;
  }

  Future<Map<int, CollectionShareStatus>> _unshareInBatches({
    required int ownerUserID,
    required int recipientUserID,
    required List<int> collectionIDs,
    required CollectionShareSource source,
  }) async {
    final statuses = {
      for (final id in collectionIDs) id: CollectionShareStatus.failed,
    };
    for (final batch in collectionIDs.chunks(_bulkShareLimit)) {
      _ensureCurrentOwner(ownerUserID);
      try {
        statuses.addAll(
          await _collectionsService.unshareBulk(
            recipientUserID: recipientUserID,
            collectionIDs: batch,
            source: source,
          ),
        );
      } catch (error, stackTrace) {
        _logger.warning('Bulk library unshare failed', error, stackTrace);
      }
    }
    return statuses;
  }

  Iterable<Collection> _eligibleAlbums() => _collectionsService
      .getCollectionsForUI(includeUncategorized: true)
      .where(
        (collection) =>
            _isShareableAlbum(collection) ||
            collection.type == CollectionType.uncategorized,
      );

  Iterable<Collection> _automaticallyShareableOwnedCollections(
    int ownerUserID,
  ) => _collectionsService.getActiveCollections().where(
    (collection) =>
        collection.isOwner(ownerUserID) &&
        (_isShareableAlbum(collection) ||
            collection.type == CollectionType.uncategorized),
  );

  static bool _isShareableAlbum(Collection collection) {
    final isSupportedType =
        collection.type == CollectionType.album ||
        collection.type == CollectionType.folder ||
        collection.type == CollectionType.favorites;
    return isSupportedType &&
        collection.magicMetadata.subType != subTypeSharedFilesCollection;
  }

  static bool _isHiddenOwnedAlbum(Collection collection) =>
      collection.isDefaultHidden() ||
      collection.mMdVersion > 0 &&
          collection.magicMetadata.visibility == hiddenVisibility;

  int _currentOwnerUserID() =>
      _configuration.getUserID() ??
      (throw StateError('Library sharing requires a signed-in account'));

  void _ensureCurrentOwner(int ownerUserID) {
    if (_configuration.getUserID() != ownerUserID) {
      throw StateError('The active account changed during library sharing');
    }
  }

  Future<LibrarySharingConfig> _writeConfig(
    int ownerUserID,
    LibrarySharingConfig config,
  ) {
    _ensureCurrentOwner(ownerUserID);
    return _store.write(ownerUserID, config);
  }

  Future<String> _requirePublicKey(String email) async {
    final publicKey = await _userService.getPublicKey(email);
    if (publicKey == null || publicKey.isEmpty) {
      throw StateError('No Ente public key found for recipient');
    }
    return publicKey;
  }

  String _recipientEmail(int recipientUserID) {
    String? email;
    for (final user in _userService.getRelevantContacts()) {
      if (user.userID == recipientUserID) {
        email = knownContactEmailOrNull(user.email) ?? email;
      }
    }
    return email ??
        (throw StateError('No email found for library sharing recipient'));
  }

  Future<void> _refreshFamilyAndHandleIneligibleRecipient(
    int ownerUserID,
    LibrarySharingConfig config,
  ) async {
    UserDetails userDetails;
    try {
      userDetails = await _userService.getUserDetailsV2(memoryCount: false);
    } catch (refreshError, refreshStackTrace) {
      _logger.warning(
        'Could not refresh family details after automatic share rejection for '
        '${config.recipientUserID}',
        refreshError,
        refreshStackTrace,
      );
      return;
    }
    if (_activeFamilyMemberUserIDs(
      userDetails,
    )!.contains(config.recipientUserID)) {
      _logger.warning(
        'Automatic share rejected for active family member '
        '${config.recipientUserID}',
      );
      return;
    }
    await _writeConfig(ownerUserID, config.copyWith(enabled: false));
  }

  Set<int>? _activeFamilyMemberUserIDs([UserDetails? userDetails]) {
    // Temporary best-effort guard while Library Sharing is family-scoped;
    // cached details can lag membership changes made on another client.
    userDetails ??= _userService.getCachedUserDetails();
    if (userDetails == null) {
      return null;
    }
    return userDetails.familyData?.members
            ?.where((member) => member.isActive)
            .map((member) => member.userID)
            .whereType<int>()
            .toSet() ??
        const {};
  }

  bool _isShareSuccess(CollectionShareStatus? status) =>
      status == CollectionShareStatus.shared ||
      status == CollectionShareStatus.alreadyShared;

  bool _isAutomaticShareSuccess(CollectionShareStatus? status) =>
      _isShareSuccess(status) ||
      status == CollectionShareStatus.blockedPreviousRemoval;

  bool _isUnshareSuccess(CollectionShareStatus status) =>
      status == CollectionShareStatus.unshared ||
      status == CollectionShareStatus.alreadyUnshared ||
      status == CollectionShareStatus.notShared;

  Map<int, int> sharedAlbumCounts(Set<int> recipientUserIDs) {
    if (recipientUserIDs.isEmpty) {
      return const {};
    }
    final counts = {for (final userID in recipientUserIDs) userID: 0};
    for (final album in _eligibleAlbums()) {
      for (final userID in recipientUserIDs) {
        if (librarySharingRoleFor(album, userID) != null) {
          counts[userID] = counts[userID]! + 1;
        }
      }
    }
    return counts;
  }
}
