import "dart:math" as math;

import "package:flutter/foundation.dart";
import "package:logging/logging.dart";
import "package:photo_manager/photo_manager.dart";
import "package:photos/core/constants.dart";
import "package:photos/ui/device_picker/device_media_library.dart";

class DevicePickerController extends ChangeNotifier {
  DevicePickerController({required this.library});

  final DeviceMediaLibrary library;
  final selectionChanges = ChangeNotifier();
  final _mediaIDs = <String>{};
  List<AssetEntity>? _selectionSnapshot;
  static const batchSize = 96;
  final _log = Logger("DevicePicker");
  final _chosen = <String, AssetEntity>{};
  final _loadedCounts = <String, int>{};
  List<AssetPathEntity> albums = [];
  List<AssetEntity> media = [];
  AssetPathEntity? album;
  PermissionState permission = PermissionState.notDetermined;
  bool refreshing = false;
  bool loadingMore = false;
  bool hasMore = false;
  bool confirming = false;
  Object? error;
  int removedSelections = 0;
  int _revision = 0;
  int _nextOffset = 0;
  bool _closed = false;

  List<AssetEntity> get selection =>
      _selectionSnapshot ??= List.unmodifiable(_chosen.values);
  int get selectionCount => _chosen.length;
  bool get hasAccess => permission.hasAccess;

  void replaceSelection(Iterable<AssetEntity> items) {
    if (confirming) return;
    final next = <String, AssetEntity>{};
    for (final item in items) {
      if (next.length >= maxPickAssetLimit) break;
      next[item.id] = item;
    }
    if (mapEquals(_chosen, next)) return;
    _chosen
      ..clear()
      ..addAll(next);
    _selectionChanged();
  }

  void _selectionChanged() {
    _selectionSnapshot = null;
    selectionChanges.notifyListeners();
  }

  void clearSelection() {
    if (confirming) return;
    _chosen.clear();
    _selectionChanged();
  }

  Future<void> refresh({bool requestPermission = false}) async {
    final revision = ++_revision;
    refreshing = true;
    loadingMore = false;
    error = null;
    notifyListeners();
    try {
      final access = await library.permission(request: requestPermission);
      if (!_isCurrent(revision)) return;
      permission = access;
      if (!access.hasAccess) {
        removedSelections += _chosen.length;
        _chosen.clear();
        _selectionChanged();
        albums = [];
        album = null;
        media = [];
        _mediaIDs.clear();
        hasMore = false;
        return;
      }
      final folders = await library.albums();
      if (!_isCurrent(revision)) return;
      final previousID = album?.id;
      final nextAlbum =
          folders.where((item) => item.id == previousID).firstOrNull ??
          folders.where((item) => item.isAll).firstOrNull ??
          folders.firstOrNull;
      final length = nextAlbum?.id == previousID
          ? math.max(batchSize, _nextOffset)
          : batchSize;
      final items = nextAlbum == null
          ? <AssetEntity>[]
          : await library.read(nextAlbum, start: 0, end: length);
      if (!_isCurrent(revision)) return;
      albums = folders;
      album = nextAlbum;
      media = _unique(items);
      _mediaIDs
        ..clear()
        ..addAll(media.map((item) => item.id));
      _nextOffset = items.length;
      hasMore = album != null && items.length == length;
      final selected = await _resolveSelection();
      if (!_isCurrent(revision)) return;
      _replaceSelection(selected.items, selected.checked);
    } catch (exception, stack) {
      if (_isCurrent(revision)) {
        error = exception;
        hasMore = false;
        _log.warning("Could not refresh device media", exception, stack);
      }
    } finally {
      if (_isCurrent(revision)) {
        refreshing = false;
        notifyListeners();
      }
    }
  }

  Future<void> openAlbum(AssetPathEntity target) async {
    if (target.id == album?.id) return;
    final revision = ++_revision;
    if (album != null) _loadedCounts[album!.id] = _nextOffset;
    album = target;
    media = [];
    _mediaIDs.clear();
    _nextOffset = 0;
    hasMore = true;
    refreshing = false;
    loadingMore = false;
    error = null;
    notifyListeners();
    await _readNext(
      revision,
      count: math.max(batchSize, _loadedCounts[target.id] ?? 0),
    );
  }

  Future<void> loadMore() async {
    if (refreshing || loadingMore || !hasMore || album == null) return;
    await _readNext(_revision);
  }

  Future<void> _readNext(int revision, {int count = batchSize}) async {
    loadingMore = true;
    error = null;
    if (media.isEmpty) notifyListeners();
    try {
      final items = await library.read(
        album!,
        start: _nextOffset,
        end: _nextOffset + count,
      );
      if (!_isCurrent(revision)) return;
      media.addAll(items.where((item) => _mediaIDs.add(item.id)));
      _nextOffset += items.length;
      hasMore = items.length == count;
    } catch (exception, stack) {
      if (_isCurrent(revision)) {
        error = exception;
        _log.warning("Could not load device media", exception, stack);
      }
    } finally {
      if (_isCurrent(revision)) {
        loadingMore = false;
        notifyListeners();
      }
    }
  }

  Future<List<AssetEntity>?> confirm() async {
    if (confirming || refreshing || _chosen.isEmpty) {
      return null;
    }
    confirming = true;
    final revision = _revision;
    notifyListeners();
    try {
      final resolved = await _resolveSelection();
      if (!_isCurrent(revision)) return null;
      final items = resolved.items;
      final previousCount = _chosen.length;
      _replaceSelection(items, resolved.checked);
      if (items.length != previousCount) return null;
      return selection;
    } catch (exception, stack) {
      if (_isCurrent(revision)) {
        _log.warning("Could not confirm device media", exception, stack);
        rethrow;
      }
      return null;
    } finally {
      if (!_closed) {
        confirming = false;
        notifyListeners();
      }
    }
  }

  Future<({List<AssetEntity> items, Set<String> checked})>
  _resolveSelection() async {
    final revision = _revision;
    final ids = _chosen.keys.toList();
    final resolved = <AssetEntity>[];
    for (var offset = 0; offset < ids.length; offset += 8) {
      final batch = await Future.wait(
        ids.skip(offset).take(8).map(library.resolve),
      );
      if (!_isCurrent(revision)) break;
      resolved.addAll(batch.whereType<AssetEntity>());
    }
    return (items: resolved, checked: ids.toSet());
  }

  void _replaceSelection(List<AssetEntity> items, Set<String> checked) {
    final byID = {for (final item in items) item.id: item};
    final missing = checked
        .where((id) => _chosen.containsKey(id) && !byID.containsKey(id))
        .toList();
    removedSelections += missing.length;
    for (final id in missing) {
      _chosen.remove(id);
    }
    for (final item in items) {
      if (_chosen.containsKey(item.id)) _chosen[item.id] = item;
    }
    _selectionChanged();
  }

  List<AssetEntity> _unique(List<AssetEntity> items) =>
      {for (final item in items) item.id: item}.values.toList();

  bool _isCurrent(int revision) => !_closed && revision == _revision;

  @override
  void dispose() {
    _closed = true;
    ++_revision;
    selectionChanges.dispose();
    super.dispose();
  }
}
