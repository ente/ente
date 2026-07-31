import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:photos/models/collection/collection.dart';
import 'package:photos/models/library_sharing/library_sharing_recipient.dart';
import 'package:photos/services/library_sharing_service.dart';

enum _LibrarySharingSelectionMode { add, manage }

class LibrarySharingController extends ChangeNotifier {
  LibrarySharingController({
    required this.recipient,
    required LibrarySharingRepository repository,
  }) : _repository = repository;

  final LibrarySharingRecipient recipient;
  final LibrarySharingRepository _repository;
  final _logger = Logger('LibrarySharingController');

  List<Collection> _albums = const [];
  final Map<int, CollectionParticipantRole> _activeRoles = {};
  final Map<int, CollectionParticipantRole> _selectedRoles = {};
  CollectionParticipantRole _defaultRole = CollectionParticipantRole.viewer;
  Object? _loadError;
  int _failedCount = 0;
  bool _isLoading = true;
  bool _isMutating = false;
  _LibrarySharingSelectionMode? _selectionMode;
  bool _isDisposed = false;

  int get eligibleAlbumCount => _albums.length;
  int get selectableAlbumCount => _albums.where(_isVisible).length;
  List<Collection> get visibleAlbums =>
      List.unmodifiable(_albums.where(_isVisible));
  List<Collection> get selectedAlbums => _albums
      .where((album) => _selectedRoles.containsKey(album.id))
      .toList(growable: false);
  int get failedCount => _failedCount;
  Object? get loadError => _loadError;
  bool get isLoading => _isLoading;
  bool get isMutating => _isMutating;
  bool get isFirstTime => _activeRoles.isEmpty;
  bool get isAddingAlbums =>
      isFirstTime || _selectionMode == _LibrarySharingSelectionMode.add;
  bool get isSelecting =>
      !_isLoading &&
      _loadError == null &&
      (_selectionMode != null || isFirstTime);
  bool get hasSelection => _selectedRoles.isNotEmpty;
  int get selectedCount => _selectedRoles.length;
  int get selectedActiveShareCount =>
      _selectedRoles.keys.where(_isShared).length;
  bool get canStopSharing => selectedActiveShareCount > 0 && !_isMutating;
  bool get canApply => hasSelection && !_isMutating;

  CollectionParticipantRole? get selectedRole {
    if (_selectedRoles.isEmpty) {
      return _defaultRole;
    }
    final role = _selectedRoles.values.first;
    return _selectedRoles.values.every((value) => value == role) ? role : null;
  }

  Future<void> load() async {
    if (_isDisposed || _isMutating) {
      return;
    }
    _isLoading = true;
    _loadError = null;
    _notifyListeners();
    try {
      await _reloadAlbums();
    } catch (error) {
      _loadError = error;
    } finally {
      _isLoading = false;
      _notifyListeners();
    }
  }

  void enterAddMode() => _enterSelectionMode(_LibrarySharingSelectionMode.add);

  void enterManageMode() =>
      _enterSelectionMode(_LibrarySharingSelectionMode.manage);

  void _enterSelectionMode(_LibrarySharingSelectionMode mode) {
    if (_isLoading || _loadError != null || _isMutating) {
      return;
    }
    if (_selectionMode != mode) {
      _clearSelectionState();
    }
    _selectionMode = mode;
    _notifyListeners();
  }

  void exitSelectionMode() {
    if (isFirstTime || _isMutating) {
      return;
    }
    _selectionMode = null;
    _clearSelectionState();
    _notifyListeners();
  }

  bool isSelected(Collection collection) =>
      _selectedRoles.containsKey(collection.id);

  CollectionParticipantRole? activeRoleFor(int collectionID) =>
      _activeRoles[collectionID];

  CollectionParticipantRole stagedRoleFor(int collectionID) =>
      _selectedRoles[collectionID] ??
      activeRoleFor(collectionID) ??
      _defaultRole;

  void toggleSelection(Collection collection) {
    if (_isMutating || !isSelecting || !_isVisible(collection)) {
      return;
    }
    final id = collection.id;
    _failedCount = 0;
    if (_selectedRoles.remove(id) == null) {
      _selectedRoles[id] = activeRoleFor(id) ?? _defaultRole;
    }
    _exitEmptyManageMode();
    _notifyListeners();
  }

  void selectAll() {
    if (_isMutating || !isSelecting) {
      return;
    }
    for (final album in _albums.where(_isVisible)) {
      _selectedRoles[album.id] ??= activeRoleFor(album.id) ?? _defaultRole;
    }
    _failedCount = 0;
    _notifyListeners();
  }

  void clearSelection() {
    if (_isMutating) {
      return;
    }
    _clearSelectionState();
    _exitEmptyManageMode();
    _notifyListeners();
  }

  void setRoleForSelection(CollectionParticipantRole role) {
    if (_isMutating) {
      return;
    }
    _defaultRole = role;
    _selectedRoles.updateAll((_, _) => role);
    _notifyListeners();
  }

  void setRoleForAlbum(int collectionID, CollectionParticipantRole role) {
    if (_isMutating || !_selectedRoles.containsKey(collectionID)) {
      return;
    }
    _selectedRoles[collectionID] = role;
    _notifyListeners();
  }

  Future<bool> applySelection() async {
    if (!canApply) {
      return false;
    }
    final intendedRoles = {
      for (final entry in _selectedRoles.entries)
        if (_activeRoles[entry.key] != entry.value) entry.key: entry.value,
    };
    if (intendedRoles.isEmpty) {
      exitSelectionMode();
      return true;
    }

    _beginMutation();
    late final String publicKey;
    try {
      final key = await _repository.getPublicKey(recipient.email);
      if (key == null || key.isEmpty) {
        throw StateError('No Ente public key found for recipient');
      }
      publicKey = key;
    } catch (error, stackTrace) {
      _logger.warning(
        'Failed to fetch recipient public key',
        error,
        stackTrace,
      );
      _isMutating = false;
      _notifyListeners();
      return false;
    }

    return _mutateAlbums(
      intendedRoles.keys.toSet(),
      (album, collectionID) => _repository.shareAlbum(
        collection: album,
        email: recipient.email,
        publicKey: publicKey,
        role: intendedRoles[collectionID]!,
      ),
      onSucceeded: (collectionID) {
        _activeRoles[collectionID] = intendedRoles[collectionID]!;
      },
    );
  }

  Future<bool> stopSharingSelected() async {
    if (!canStopSharing) {
      return false;
    }
    final pendingIDs = _selectedRoles.keys.where(_isShared).toSet();
    _beginMutation();
    return _mutateAlbums(
      pendingIDs,
      (album, _) => _repository.unshareAlbum(
        collection: album,
        recipientUserID: recipient.userID,
        email: recipient.email,
      ),
      onSucceeded: _activeRoles.remove,
    );
  }

  void _beginMutation() {
    _isMutating = true;
    _failedCount = 0;
    _notifyListeners();
  }

  Future<bool> _mutateAlbums(
    Set<int> collectionIDs,
    Future<void> Function(Collection album, int collectionID) mutate, {
    required ValueChanged<int> onSucceeded,
  }) async {
    final failedIDs = <int>{};
    final albumsByID = {for (final album in _albums) album.id: album};
    for (final collectionID in collectionIDs) {
      final album = albumsByID[collectionID];
      if (album == null) {
        failedIDs.add(collectionID);
        continue;
      }
      try {
        await mutate(album, collectionID);
      } catch (error, stackTrace) {
        _logger.warning(
          'Failed to update album $collectionID',
          error,
          stackTrace,
        );
        failedIDs.add(collectionID);
      }
    }
    return _finishMutation(
      collectionIDs,
      failedIDs: failedIDs,
      onSucceeded: onSucceeded,
    );
  }

  Future<bool> _finishMutation(
    Set<int> attemptedIDs, {
    required Set<int> failedIDs,
    required ValueChanged<int> onSucceeded,
  }) async {
    final succeededIDs = attemptedIDs.difference(failedIDs);
    for (final id in succeededIDs) {
      _selectedRoles.remove(id);
      onSucceeded(id);
    }
    _selectedRoles.removeWhere((id, _) => !failedIDs.contains(id));
    try {
      await _reloadAlbums();
    } catch (error, stackTrace) {
      _logger.warning(
        'Failed to reload albums after sharing update',
        error,
        stackTrace,
      );
    }
    failedIDs.removeWhere((id) => !_selectedRoles.containsKey(id));
    _failedCount = failedIDs.length;
    _isMutating = false;
    if (failedIDs.isEmpty) {
      _selectionMode = null;
    }
    _notifyListeners();
    return failedIDs.isEmpty;
  }

  Future<void> _reloadAlbums() async {
    _albums = await _repository.getEligibleAlbums();
    _activeRoles.clear();
    for (final album in _albums) {
      final role = librarySharingRoleFor(album, recipient.userID);
      if (role != null) {
        _activeRoles[album.id] = role;
      }
    }
    final selectableIDs = _albums
        .where(_isVisible)
        .map((album) => album.id)
        .toSet();
    _selectedRoles.removeWhere((id, _) => !selectableIDs.contains(id));
    _exitEmptyManageMode();
  }

  bool _isShared(int collectionID) => _activeRoles.containsKey(collectionID);

  bool _isVisible(Collection album) =>
      isAddingAlbums ? !_isShared(album.id) : _isShared(album.id);

  void _clearSelectionState() {
    _selectedRoles.clear();
    _failedCount = 0;
  }

  void _exitEmptyManageMode() {
    if (_selectionMode == _LibrarySharingSelectionMode.manage &&
        _selectedRoles.isEmpty) {
      _selectionMode = null;
    }
  }

  void _notifyListeners() {
    if (!_isDisposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }
}
