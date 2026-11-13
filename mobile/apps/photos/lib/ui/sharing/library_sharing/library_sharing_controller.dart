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
  bool _isAutomaticSharingEnabled = false;
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
  bool get isAutomaticSharingEnabled => _isAutomaticSharingEnabled;
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
  bool get canEditSelectedRoles =>
      !_isMutating &&
      selectedAlbums.any((album) => album.type != CollectionType.uncategorized);

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
      _isAutomaticSharingEnabled = await _repository.isAutomaticSharingEnabled(
        recipient.userID,
      );
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

  CollectionParticipantRole stagedRoleFor(int collectionID) {
    final role =
        _selectedRoles[collectionID] ??
        activeRoleFor(collectionID) ??
        _defaultRole;
    return normalizeLibrarySharingRole(
      _albums.firstWhere((album) => album.id == collectionID),
      role,
    );
  }

  void toggleSelection(Collection collection) {
    if (_isMutating || !isSelecting || !_isVisible(collection)) {
      return;
    }
    final id = collection.id;
    _failedCount = 0;
    if (_selectedRoles.remove(id) == null) {
      _selectedRoles[id] = stagedRoleFor(id);
    }
    _exitEmptyManageMode();
    _notifyListeners();
  }

  void selectAll() {
    if (_isMutating || !isSelecting) {
      return;
    }
    for (final album in _albums.where(_isVisible)) {
      _selectedRoles[album.id] ??= stagedRoleFor(album.id);
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
    for (final album in selectedAlbums) {
      _selectedRoles[album.id] = normalizeLibrarySharingRole(album, role);
    }
    _notifyListeners();
  }

  void setRoleForAlbum(int collectionID, CollectionParticipantRole role) {
    if (_isMutating || !_selectedRoles.containsKey(collectionID)) {
      return;
    }
    final album = _albums.firstWhere((album) => album.id == collectionID);
    _selectedRoles[collectionID] = normalizeLibrarySharingRole(album, role);
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
    return _mutateAlbums(
      intendedRoles.keys.toSet(),
      () => _repository.shareAlbums(recipient: recipient, roles: intendedRoles),
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
      () => _repository.unshareAlbums(
        recipientUserID: recipient.userID,
        collectionIDs: pendingIDs.toList(),
      ),
      onSucceeded: _activeRoles.remove,
    );
  }

  Future<EnableAutomaticSharingResult?> enableAutomaticSharing(
    CollectionParticipantRole role,
  ) async {
    if (_isLoading || _isMutating || _isAutomaticSharingEnabled) {
      return null;
    }
    _beginMutation();
    try {
      final result = await _repository.enableAutomaticSharing(
        recipient: recipient,
        role: role,
      );
      await _reloadAfterMutation();
      _failedCount = result.failedIDs.length;
      _isAutomaticSharingEnabled = result.failedIDs.isEmpty;
      if (result.failedIDs.isEmpty) {
        _selectionMode = null;
        _clearSelectionState();
      }
      return result;
    } catch (error, stackTrace) {
      _logger.warning(
        'Failed to enable automatic library sharing',
        error,
        stackTrace,
      );
      return null;
    } finally {
      _isMutating = false;
      _notifyListeners();
    }
  }

  Future<bool> disableAutomaticSharing() async {
    if (_isLoading || _isMutating || !_isAutomaticSharingEnabled) {
      return false;
    }
    _beginMutation();
    try {
      await _repository.disableAutomaticSharing(recipient.userID);
      _isAutomaticSharingEnabled = false;
      return true;
    } catch (error, stackTrace) {
      _logger.warning(
        'Failed to disable automatic library sharing',
        error,
        stackTrace,
      );
      return false;
    } finally {
      _isMutating = false;
      _notifyListeners();
    }
  }

  void _beginMutation() {
    _isMutating = true;
    _failedCount = 0;
    _notifyListeners();
  }

  Future<bool> _mutateAlbums(
    Set<int> collectionIDs,
    Future<Set<int>> Function() mutate, {
    required ValueChanged<int> onSucceeded,
  }) async {
    late Set<int> failedIDs;
    try {
      failedIDs = {...await mutate()};
    } catch (error, stackTrace) {
      _logger.warning('Failed to update albums', error, stackTrace);
      failedIDs = collectionIDs;
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
    await _reloadAfterMutation();
    failedIDs.removeWhere((id) => !_selectedRoles.containsKey(id));
    _failedCount = failedIDs.length;
    _isMutating = false;
    if (failedIDs.isEmpty) {
      _selectionMode = null;
    }
    _notifyListeners();
    return failedIDs.isEmpty;
  }

  Future<void> _reloadAfterMutation() async {
    try {
      await _reloadAlbums();
    } catch (error, stackTrace) {
      _logger.warning(
        'Failed to reload albums after sharing update',
        error,
        stackTrace,
      );
    }
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
