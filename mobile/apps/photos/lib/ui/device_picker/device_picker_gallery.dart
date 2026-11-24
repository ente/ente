import "dart:async";

import "package:collection/collection.dart";
import "package:flutter/foundation.dart";
import "package:flutter/material.dart";
import "package:logging/logging.dart";
import "package:photo_manager/photo_manager.dart";
import "package:photos/events/files_updated_event.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/file_load_result.dart";
import "package:photos/models/gallery_type.dart";
import "package:photos/models/selected_files.dart";
import "package:photos/module/metadata/local_file.dart";
import "package:photos/ui/device_picker/device_media_library.dart";
import "package:photos/ui/device_picker/device_picker_controller.dart";
import "package:photos/ui/device_picker/device_picker_selection.dart";
import "package:photos/ui/viewer/gallery/gallery.dart";
import "package:photos/ui/viewer/gallery/state/gallery_files_inherited_widget.dart";

class DevicePickerGallery extends StatefulWidget {
  const DevicePickerGallery({
    super.key,
    required this.model,
    required this.footer,
    this.header,
    this.selectedFiles,
  });

  final DevicePickerController model;
  final Widget footer;
  final Widget? header;
  final SelectedFiles? selectedFiles;

  @override
  State<DevicePickerGallery> createState() => _DevicePickerGalleryState();
}

class _DevicePickerGalleryState extends State<DevicePickerGallery> {
  late final _selection = DevicePickerSelectedFiles(
    selectionLimit: widget.model.selectionLimit,
  );
  final _reload = StreamController<FilesUpdatedEvent>.broadcast();
  final _assets = <String, AssetEntity>{};
  final _files = <String, EnteFile>{};
  List<AssetEntity> _snapshot = [];
  final _resolvedIDs = <String>{};
  bool _syncingSelection = false;
  bool _loadScheduled = false;
  double? _loadExtent;

  EnteFile _fileFor(AssetEntity item) {
    final file = _files.putIfAbsent(
      item.id,
      () => fileFromAsset(widget.model.album?.name ?? '', item),
    );
    if (widget.selectedFiles == null) _selection.register(file, item.id);
    if (file.duration == null || file.duration == 0) {
      file.duration = item.duration;
    }
    return file;
  }

  @override
  void initState() {
    super.initState();
    _updateFiles();
    widget.model.addListener(_modelChanged);
    if (widget.selectedFiles == null) {
      _readSelection();
      _selection.addListener(_writeSelection);
      widget.model.selectionChanges.addListener(_readSelection);
    }
  }

  void _updateFiles() {
    _snapshot = List.of(widget.model.media);
    final available = {
      for (final item in widget.model.selection) item.id: item,
      for (final item in _snapshot) item.id: item,
    };
    final ids = available.keys.toSet();
    _assets.removeWhere((id, _) => !ids.contains(id));
    _files.removeWhere((id, _) => !ids.contains(id));
    _resolvedIDs.retainAll(ids);
    for (final item in available.values) {
      if (!identical(_assets[item.id], item)) {
        _files.remove(item.id);
        _resolvedIDs.remove(item.id);
      }
      _assets[item.id] = item;
    }
  }

  void _modelChanged() {
    if (widget.selectedFiles == null) {
      _selection.locked = widget.model.confirming;
    }
    if (const ListEquality<AssetEntity>(
      IdentityEquality(),
    ).equals(_snapshot, widget.model.media)) {
      return;
    }
    _updateFiles();
    _reload.add(FilesUpdatedEvent([]));
  }

  Future<FileLoadResult> _loadFiles() async {
    final snapshot = _snapshot;
    final ids = snapshot
        .map((item) => item.id)
        .where((id) => !_resolvedIDs.contains(id))
        .toList();
    final files = await widget.model.library.files(ids).catchError((
      Object error,
      StackTrace stack,
    ) {
      Logger(
        "DevicePicker",
      ).warning("Could not read file metadata", error, stack);
      return <String, EnteFile>{};
    });
    if (!mounted) return FileLoadResult([], false);
    if (!identical(snapshot, _snapshot)) return _loadFiles();
    _resolvedIDs.addAll(ids);
    if (widget.selectedFiles == null) {
      _files.addAll(files);
      _readSelection();
    } else {
      for (final entry in files.entries) {
        _files[entry.key] = devicePickerFileFromAsset(
          widget.model.album?.name ?? '',
          _assets[entry.key]!,
          entry.value,
        );
      }
    }
    return FileLoadResult(
      snapshot
          .map(_fileFor)
          .sortedByCompare(
            (file) => file.creationTime ?? 0,
            (first, second) => second.compareTo(first),
          ),
      false,
    );
  }

  void _readSelection() {
    if (_syncingSelection) return;
    _syncingSelection = true;
    try {
      final next = widget.model.selection.map(_fileFor).toSet();
      if (!setEquals(_selection.files, next)) _selection.replaceSelection(next);
    } finally {
      _syncingSelection = false;
    }
  }

  void _writeSelection() {
    if (_syncingSelection) return;
    _syncingSelection = true;
    try {
      widget.model.replaceSelection(
        _selection.files
            .map((file) => _assets[_selection.assetID(file)])
            .nonNulls,
      );
    } finally {
      _syncingSelection = false;
    }
    if (_selection.files.length != widget.model.selectionCount) {
      _readSelection();
    }
  }

  void _loadMore(ScrollMetrics metrics) {
    if (metrics.extentAfter >= 600) _loadExtent = null;
    if (metrics.axis != Axis.vertical ||
        metrics.extentAfter >= 600 ||
        _loadExtent == metrics.maxScrollExtent ||
        !widget.model.hasMore ||
        widget.model.loadingMore ||
        widget.model.error != null ||
        _loadScheduled) {
      return;
    }
    _loadExtent = metrics.maxScrollExtent;
    _loadScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadScheduled = false;
      if (mounted) unawaited(widget.model.loadMore());
    });
  }

  @override
  void dispose() {
    widget.model.removeListener(_modelChanged);
    if (widget.selectedFiles == null) {
      widget.model.selectionChanges.removeListener(_readSelection);
      _selection.dispose();
    }
    unawaited(_reload.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      NotificationListener<ScrollMetricsNotification>(
        onNotification: (notification) {
          if (notification.depth == 0) _loadMore(notification.metrics);
          return false;
        },
        child: NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            if (notification.depth == 0) _loadMore(notification.metrics);
            return false;
          },
          child: GalleryFilesState(
            child: Gallery(
              key: widget.model.browsingFilenameMatches
                  ? ValueKey(widget.model.album?.name)
                  : PageStorageKey(widget.model.album?.id),
              asyncLoader: (_, _, {limit, asc}) => _loadFiles(),
              reloadEvent: _reload.stream,
              reloadDebounceTime: Duration.zero,
              reloadDebounceExecutionInterval: Duration.zero,
              tagPrefix: 'device_picker_gallery',
              albumName: widget.model.album?.name ?? '',
              galleryType: GalleryType.localFolder,
              selectedFiles: widget.selectedFiles ?? _selection,
              inSelectionMode: true,
              limitSelectionToOne: widget.model.selectionLimit == 1,
              showSelectAll:
                  widget.selectedFiles == null &&
                  widget.model.selectionLimit != 1,
              disableSelection: widget.model.confirming,
              disablePinnedGroupHeader: true,
              disableVerticalPaddingForScrollbar: true,
              header: widget.header,
              footer: widget.footer,
            ),
          ),
        ),
      );
}
