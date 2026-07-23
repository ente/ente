import 'dart:async';
import "dart:math";

import "package:ente_components/ente_components.dart";
import "package:ente_pure_utils/ente_pure_utils.dart";
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:photos/core/event_bus.dart';
import 'package:photos/db/device_files_db.dart';
import 'package:photos/db/files_db.dart';
import 'package:photos/events/backup_folders_updated_event.dart';
import 'package:photos/events/local_photos_updated_event.dart';
import "package:photos/generated/l10n.dart";
import 'package:photos/models/device_collection.dart';
import "package:photos/service_locator.dart";
import "package:photos/settings/local_settings.dart";
import "package:photos/ui/collections/device/device_folder_list_item.dart";
import "package:photos/ui/collections/device/device_folder_row_item.dart";
import 'package:photos/ui/common/loading_widget.dart';
import 'package:photos/ui/components/searchable_appbar.dart';
import "package:photos/ui/tabs/albums/empty_states/on_device_empty_state.dart";
import 'package:photos/ui/viewer/gallery/empty_state.dart';
import "package:photos/utils/device_collection_sort_util.dart";

class DeviceFolderVerticalGridView extends StatefulWidget {
  final Widget? appTitle;
  final String? tag;
  final bool startInSearchMode;
  const DeviceFolderVerticalGridView({
    this.appTitle,
    this.tag,
    this.startInSearchMode = false,
    super.key,
  });

  @override
  State<DeviceFolderVerticalGridView> createState() =>
      _DeviceFolderVerticalGridViewState();
}

class _DeviceFolderVerticalGridViewState
    extends State<DeviceFolderVerticalGridView> {
  String _searchQuery = "";

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: <Widget>[
          SearchableAppBar(
            title: widget.appTitle ?? const SizedBox.shrink(),
            heroTag: widget.tag ?? "",
            autoActivateSearch: widget.startInSearchMode,
            backgroundColor: Theme.of(context).scaffoldBackgroundColor,
            onSearch: (value) {
              setState(() {
                _searchQuery = value;
              });
            },
            onSearchClosed: () {
              if (_searchQuery.isNotEmpty) {
                setState(() {
                  _searchQuery = "";
                });
              }
            },
          ),
          DeviceFolderVerticalGridSliver(searchQuery: _searchQuery),
        ],
      ),
    );
  }
}

class DeviceFolderVerticalGridSliver extends StatefulWidget {
  final String searchQuery;
  final AlbumViewType albumViewType;
  final AlbumSortKey sortKey;
  final AlbumSortDirection sortDirection;
  final bool showEmptyState;
  final double topPadding;
  final double bottomPadding;
  final Widget? sectionHeader;
  final Widget? emptyStateSliver;

  const DeviceFolderVerticalGridSliver({
    required this.searchQuery,
    this.albumViewType = AlbumViewType.grid,
    this.sortKey = AlbumSortKey.newestPhoto,
    this.sortDirection = AlbumSortDirection.ascending,
    this.showEmptyState = true,
    this.topPadding = 16,
    this.bottomPadding = 200,
    this.sectionHeader,
    this.emptyStateSliver,
    super.key,
  });

  @override
  State<DeviceFolderVerticalGridSliver> createState() =>
      _DeviceFolderVerticalGridViewBodyState();
}

class _DeviceFolderVerticalGridViewBodyState
    extends State<DeviceFolderVerticalGridSliver> {
  static List<DeviceCollection>? _cachedDeviceCollections;

  StreamSubscription<BackupFoldersUpdatedEvent>? _backupFoldersUpdatedEvent;
  StreamSubscription<LocalPhotosUpdatedEvent>? _localFilesSubscription;
  late Future<List<DeviceCollection>> _deviceCollectionsFuture;
  final logger = Logger((_DeviceFolderVerticalGridViewBodyState).toString());
  final _debouncer = Debouncer(
    const Duration(milliseconds: 1500),
    executionInterval: const Duration(seconds: 4),
  );
  /*
  Aspect ratio 1:1
  Width changes dynamically with screen width
  */
  static const maxThumbnailWidth = 224.0;
  static const horizontalPadding = 16.0;
  static const crossAxisSpacing = 8.0;
  static const listItemSpacing = 8.0;
  static const _thumbnailToTextSpacing = 8.0;
  static const _titleToSubtitleSpacing = 4.0;

  @override
  void initState() {
    super.initState();
    _deviceCollectionsFuture = _loadDeviceCollections();
    _backupFoldersUpdatedEvent = Bus.instance
        .on<BackupFoldersUpdatedEvent>()
        .listen((_) {
          _refreshDeviceCollections();
        });
    _localFilesSubscription = Bus.instance.on<LocalPhotosUpdatedEvent>().listen(
      (_) {
        _debouncer.run(() async {
          _refreshDeviceCollections();
        });
      },
    );
  }

  Future<List<DeviceCollection>> _loadDeviceCollections() async {
    final deviceCollections = await FilesDB.instance.getDeviceCollections(
      includeCoverThumbnail: true,
    );
    _cachedDeviceCollections = deviceCollections;
    return deviceCollections;
  }

  void _refreshDeviceCollections() {
    if (!mounted) {
      return;
    }
    setState(() {
      _deviceCollectionsFuture = _loadDeviceCollections();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (backupPreferenceService.hasSkippedOnboardingPermission) {
      if (widget.emptyStateSliver != null) {
        return widget.emptyStateSliver!;
      }
      return widget.showEmptyState
          ? SliverFillRemaining(
              hasScrollBody: false,
              child: OnDeviceEmptyState.permission(
                onFoldersSelected: () {
                  _refreshDeviceCollections();
                },
              ),
            )
          : const SliverToBoxAdapter(child: SizedBox.shrink());
    }

    return FutureBuilder<List<DeviceCollection>>(
      future: _deviceCollectionsFuture,
      initialData: _cachedDeviceCollections,
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          List<DeviceCollection> deviceCollections = snapshot.data!.toList();
          final hasDeviceCollections = deviceCollections.isNotEmpty;
          if (widget.searchQuery.isNotEmpty) {
            final String query = widget.searchQuery.toLowerCase();
            deviceCollections = deviceCollections
                .where(
                  (deviceCollection) =>
                      deviceCollection.name.toLowerCase().contains(query),
                )
                .toList();
          }
          sortDeviceCollections(
            deviceCollections,
            widget.sortKey,
            widget.sortDirection,
          );

          if (deviceCollections.isEmpty) {
            if (widget.emptyStateSliver != null) {
              return widget.emptyStateSliver!;
            }
            return widget.showEmptyState
                ? SliverFillRemaining(
                    hasScrollBody: false,
                    child: !hasDeviceCollections
                        ? OnDeviceEmptyState.noFolders(
                            onFoldersSelected: _refreshDeviceCollections,
                          )
                        : Padding(
                            padding: const EdgeInsets.all(22),
                            child: EmptyState(
                              text: AppLocalizations.of(context).noResultsFound,
                            ),
                          ),
                  )
                : const SliverToBoxAdapter(child: SizedBox.shrink());
          }

          final contentSliver = widget.albumViewType == AlbumViewType.grid
              ? _buildGridView(context, deviceCollections)
              : _buildListView(deviceCollections);
          if (widget.sectionHeader == null) {
            return contentSliver;
          }
          return SliverMainAxisGroup(
            slivers: [
              SliverToBoxAdapter(child: widget.sectionHeader!),
              contentSliver,
            ],
          );
        } else if (snapshot.hasError) {
          logger.severe("failed to load device gallery", snapshot.error);
          return widget.showEmptyState
              ? SliverFillRemaining(
                  child: Center(
                    child: Text(
                      AppLocalizations.of(context).failedToLoadAlbums,
                    ),
                  ),
                )
              : const SliverToBoxAdapter(child: SizedBox.shrink());
        } else {
          return widget.showEmptyState
              ? const SliverFillRemaining(child: EnteLoadingWidget())
              : const SliverToBoxAdapter(child: SizedBox.shrink());
        }
      },
    );
  }

  Widget _buildGridView(
    BuildContext context,
    List<DeviceCollection> deviceCollections,
  ) {
    final double screenWidth = MediaQuery.sizeOf(context).width;
    final int albumsCountInCrossAxis = max(screenWidth ~/ maxThumbnailWidth, 3);

    final double totalCrossAxisSpacing =
        (albumsCountInCrossAxis - 1) * crossAxisSpacing;
    final double sideOfThumbnail =
        (screenWidth - totalCrossAxisSpacing - horizontalPadding) /
        albumsCountInCrossAxis;
    final double gridItemTextHeight = _gridItemTextHeight(context);

    return SliverPadding(
      padding: EdgeInsets.only(
        top: widget.topPadding,
        left: horizontalPadding / 2,
        right: horizontalPadding / 2,
        bottom: widget.bottomPadding,
      ),
      sliver: SliverGrid(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: albumsCountInCrossAxis,
          mainAxisSpacing: 24,
          crossAxisSpacing: crossAxisSpacing,
          childAspectRatio:
              sideOfThumbnail / (sideOfThumbnail + gridItemTextHeight),
        ),
        delegate: SliverChildBuilderDelegate((BuildContext context, int index) {
          final deviceCollection = deviceCollections[index];
          return DeviceFolderRowItem(
            deviceCollection,
            sideOfThumbnail: sideOfThumbnail,
          );
        }, childCount: deviceCollections.length),
      ),
    );
  }

  Widget _buildListView(List<DeviceCollection> deviceCollections) {
    return SliverPadding(
      padding: EdgeInsets.only(
        top: widget.topPadding,
        left: 8,
        right: 8,
        bottom: widget.bottomPadding,
      ),
      sliver: SliverList.builder(
        itemBuilder: (context, index) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: listItemSpacing / 2),
            child: DeviceFolderListItem(deviceCollections[index]),
          );
        },
        itemCount: deviceCollections.length,
      ),
    );
  }

  double _gridItemTextHeight(BuildContext context) {
    final textScaler = MediaQuery.textScalerOf(context);
    return (_thumbnailToTextSpacing +
            _scaledLineHeight(textScaler, TextStyles.body) +
            _titleToSubtitleSpacing +
            _scaledLineHeight(textScaler, TextStyles.mini))
        .ceilToDouble();
  }

  double _scaledLineHeight(TextScaler textScaler, TextStyle style) {
    final fontSize = style.fontSize ?? 14;
    return textScaler.scale(fontSize) * (style.height ?? 1);
  }

  @override
  void dispose() {
    _backupFoldersUpdatedEvent?.cancel();
    _localFilesSubscription?.cancel();
    _debouncer.cancelDebounceTimer();
    super.dispose();
  }
}
