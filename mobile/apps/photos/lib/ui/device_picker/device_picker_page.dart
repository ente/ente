import "dart:async";

import "package:ente_components/ente_components.dart";
import "package:ente_components/hugeicons.dart";
import "package:ente_strings/ente_strings.dart";
import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:logging/logging.dart";
import "package:photo_manager/photo_manager.dart";
import "package:photos/core/constants.dart";
import "package:photos/ente_theme_data.dart";
import "package:photos/models/selected_files.dart";
import "package:photos/module/metadata/local_file.dart";
import "package:photos/ui/components/bottom_action_bar/action_bar_widget.dart";
import "package:photos/ui/components/collection_share_badge.dart";
import "package:photos/ui/components/selection_preview_button.dart";
import "package:photos/ui/components/thumbnail_list_item.dart";
import "package:photos/ui/device_picker/device_media_library.dart";
import "package:photos/ui/device_picker/device_picker_controller.dart";
import "package:photos/ui/device_picker/device_picker_gallery.dart";
import "package:photos/ui/viewer/file/detail_page.dart";
import "package:photos/ui/viewer/file/thumbnail_widget.dart";
import "package:photos/ui/viewer/gallery/state/boundary_reporter_mixin.dart";
import "package:photos/ui/viewer/gallery/state/gallery_boundaries_provider.dart";

Future<List<AssetEntity>?> showDevicePicker(
  BuildContext context, {
  RequestType requestType = RequestType.common,
  int? selectionLimit = maxPickAssetLimit,
  bool allowEmptySelection = false,
  String? initialAlbumID,
  Iterable<AssetEntity> initialSelection = const [],
}) => Navigator.of(context).push<List<AssetEntity>>(
  MaterialPageRoute(
    builder: (_) => DevicePickerPage(
      requestType: requestType,
      selectionLimit: selectionLimit,
      allowEmptySelection: allowEmptySelection,
      initialAlbumID: initialAlbumID,
      initialSelection: initialSelection,
    ),
  ),
);

typedef DevicePickerContents = ({
  DevicePickerController model,
  Widget Function(SelectedFiles) media,
  Widget Function(ValueChanged<AssetPathEntity>) albums,
});

class DevicePickerPage extends StatefulWidget {
  const DevicePickerPage({
    super.key,
    this.library,
    this.requestType = RequestType.common,
    this.selectionLimit = maxPickAssetLimit,
    this.allowEmptySelection = false,
    this.initialAlbumID,
    this.initialSelection = const [],
    this.contentBuilder,
  }) : assert(selectionLimit == null || selectionLimit > 0);

  final Widget Function(DevicePickerContents)? contentBuilder;
  final DeviceMediaLibrary? library;
  final RequestType requestType;
  final int? selectionLimit;
  final bool allowEmptySelection;
  final String? initialAlbumID;
  final Iterable<AssetEntity> initialSelection;

  @override
  State<DevicePickerPage> createState() => _DevicePickerPageState();
}

class _DevicePickerPageState extends State<DevicePickerPage>
    with WidgetsBindingObserver {
  late final _model = DevicePickerController(
    library:
        widget.library ??
        PhotoManagerDeviceLibrary(requestType: widget.requestType),
    selectionLimit: widget.selectionLimit,
    allowEmptySelection: widget.allowEmptySelection,
    initialAlbumID: widget.initialAlbumID,
    initialSelection: widget.initialSelection,
  );
  final _albumScroll = ScrollController();
  Timer? _refreshTimer;
  bool _albumMenu = false;
  bool _starting = true;
  int _seenRemovals = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _model.addListener(_onChanged);
    if (widget.library == null) {
      PhotoManager.addChangeCallback(_onLibraryChange);
      unawaited(
        PhotoManager.startChangeNotify().catchError((Object error) {
          Logger(
            "DevicePicker",
          ).warning("Could not observe photo changes", error);
        }),
      );
    }
    unawaited(_start());
  }

  Future<void> _start() async {
    await _model.refresh(requestPermission: true);
    _starting = false;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || _starting) return;
    if (widget.contentBuilder != null) {
      _refreshTimer?.cancel();
      unawaited(_model.refresh());
    } else {
      _scheduleRefresh();
    }
  }

  void _onLibraryChange(MethodCall _) => _scheduleRefresh();

  void _scheduleRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer(Motion.slow, () {
      if (mounted && !_starting) unawaited(_model.refresh());
    });
  }

  void _onChanged() {
    if (!mounted) return;
    setState(() {});
    if (_model.removedSelections > _seenRemovals) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            (ModalRoute.of(context)?.isCurrent ?? false) &&
            _model.removedSelections > _seenRemovals) {
          _seenRemovals = _model.removedSelections;
          showToastComponent(
            context,
            context.strings.devicePickerSelectionChanged,
          );
        }
      });
    }
  }

  Future<void> _addSelected() async {
    try {
      final result = await _model.confirm();
      if (!mounted || ModalRoute.of(context)?.isCurrent != true) return;
      if (result != null) Navigator.pop(context, result);
    } catch (_) {
      if (!mounted || ModalRoute.of(context)?.isCurrent != true) return;
      showToastComponent(
        context,
        context.strings.somethingWentWrongPleaseTryAgain,
      );
    }
  }

  Future<void> _switchAlbum(AssetPathEntity album) async {
    setState(() => _albumMenu = false);
    await _model.openAlbum(album);
  }

  Future<void> _previewSelection() async {
    if (_model.selection.isEmpty || _model.confirming) return;
    setState(() => _albumMenu = false);
    final files = _model.selection
        .map((asset) => fileFromAsset('', asset)..duration = asset.duration)
        .toList();
    final shouldAdd = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => Theme(
          data: darkThemeData,
          child: Builder(
            builder: (previewContext) => AnnotatedRegion<SystemUiOverlayStyle>(
              value: SystemUiOverlayStyle.light.copyWith(
                systemNavigationBarColor:
                    previewContext.componentColors.backgroundBase,
              ),
              child: DetailPage(
                DetailPageConfiguration(
                  files,
                  files.length - 1,
                  'device_picker_selection',
                  mode: DetailPageMode.selection,
                  isLocalOnlyContext: true,
                  showEditAction: false,
                  showGalleryFilmstrip: true,
                  selectionLimit: widget.selectionLimit,
                  onSelectionRemoved: (file) => _model.replaceSelection(
                    _model.selection.where((asset) => asset.id != file.localID),
                  ),
                ),
                bottomBar: ColoredBox(
                  color: previewContext.componentColors.backgroundBase,
                  child: SafeArea(
                    top: false,
                    child: _addButton(
                      () async => Navigator.pop(previewContext, true),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    if (!mounted) return;
    final needsReview = _model.removedSelections > _seenRemovals;
    _onChanged();
    if (shouldAdd == true && !needsReview) await _addSelected();
  }

  Future<void> _manageAccess() async {
    await PhotoManager.presentLimited(type: widget.requestType);
    if (mounted) await _model.refresh();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    if (widget.library == null) {
      PhotoManager.removeChangeCallback(_onLibraryChange);
    }
    _model.removeListener(_onChanged);
    _model.dispose();
    _albumScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.contentBuilder case final builder?) {
      return builder((model: _model, media: _grid, albums: _albumList));
    }
    final colors = context.componentColors;
    return GalleryBoundariesProvider(
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value:
            (Theme.of(context).brightness == Brightness.dark
                    ? SystemUiOverlayStyle.light
                    : SystemUiOverlayStyle.dark)
                .copyWith(
                  statusBarColor: colors.backgroundBase,
                  systemNavigationBarColor: colors.backgroundBase,
                ),
        child: PopScope(
          canPop: !_albumMenu,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop && _albumMenu) setState(() => _albumMenu = false);
          },
          child: Scaffold(
            backgroundColor: colors.backgroundBase,
            body: SafeArea(
              child: Column(
                children: [
                  _DevicePickerBoundary(
                    position: BoundaryPosition.top,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: Spacing.sm,
                        vertical: Spacing.sm,
                      ),
                      child: Row(
                        children: [
                          IconButtonComponent(
                            icon: const HugeIcon(
                              icon: HugeIcons.strokeRoundedCancel01,
                              size: IconSizes.medium,
                            ),
                            tooltip: context.strings.close,
                            size: 48,
                            iconSize: IconSizes.medium,
                            onTap: () {
                              if (_albumMenu) {
                                setState(() => _albumMenu = false);
                              } else {
                                Navigator.pop(context);
                              }
                            },
                          ),
                          Expanded(
                            child: Center(
                              child: SizedBox(
                                width: 180,
                                child: FilterChipComponent(
                                  label: _albumName(context, _model.album),
                                  labelStyle: TextStyles.body,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: Spacing.md,
                                    vertical: Spacing.sm,
                                  ),
                                  tooltip: _albumName(context, _model.album),
                                  state: _albumMenu
                                      ? FilterChipComponentState.selected
                                      : FilterChipComponentState.unselected,
                                  trailing: HugeIcon(
                                    icon: _albumMenu
                                        ? HugeIcons.strokeRoundedArrowUp01
                                        : HugeIcons.strokeRoundedArrowDown01,
                                    size: IconSizes.small,
                                  ),
                                  onChanged: _model.albums.isEmpty
                                      ? null
                                      : (_) => setState(
                                          () => _albumMenu = !_albumMenu,
                                        ),
                                ),
                              ),
                            ),
                          ),
                          SizedBox.square(
                            dimension: 48,
                            child: ListenableBuilder(
                              listenable: _model.selectionChanges,
                              builder: (context, _) => _model.selection.isEmpty
                                  ? const SizedBox.shrink()
                                  : SelectionPreviewButton(
                                      file: fileFromAsset(
                                        '',
                                        _model.selection.last,
                                      ),
                                      count: _model.selectionCount,
                                      onTap: _model.confirming
                                          ? null
                                          : _previewSelection,
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Expanded(
                    child: Stack(
                      children: [
                        ExcludeSemantics(
                          excluding: _albumMenu,
                          child: Column(
                            children: [
                              Expanded(
                                child: Stack(
                                  children: [
                                    Positioned.fill(child: _grid()),
                                    PositionedDirectional(
                                      end: Spacing.lg,
                                      bottom: Spacing.sm,
                                      child: ListenableBuilder(
                                        listenable: _model.selectionChanges,
                                        builder: (context, _) {
                                          final count = _model.selectionCount;
                                          final limit = _model.selectionLimit;
                                          final summary = limit == null
                                              ? context.strings.selectedCount(
                                                  count: count,
                                                )
                                              : context.strings
                                                    .selectedCountWithLimit(
                                                      count: count,
                                                      limit: limit,
                                                    );
                                          return count > 0
                                              ? SelectionControlChip(
                                                  label: limit == null
                                                      ? count.toString()
                                                      : '$count/$limit',
                                                  semanticLabel:
                                                      '${context.strings.clearSelection}, $summary',
                                                  icon: const HugeIcon(
                                                    icon: HugeIcons
                                                        .strokeRoundedCancel01,
                                                    size: IconSizes.small,
                                                  ),
                                                  onTap: _model.confirming
                                                      ? null
                                                      : _model.clearSelection,
                                                )
                                              : const SizedBox.shrink();
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              _DevicePickerBoundary(
                                position: BoundaryPosition.bottom,
                                child: _addButton(_addSelected),
                              ),
                            ],
                          ),
                        ),
                        if (_albumMenu) ...[
                          ModalBarrier(
                            color: colors.specialScrim,
                            dismissible: true,
                            semanticsLabel: context.strings.close,
                            onDismiss: () => setState(() => _albumMenu = false),
                          ),
                          LayoutBuilder(
                            builder: (context, constraints) => Align(
                              alignment: Alignment.topCenter,
                              child: ConstrainedBox(
                                constraints: BoxConstraints(
                                  maxHeight: constraints.maxHeight * 0.72,
                                  maxWidth: 428,
                                ),
                                child: Material(
                                  color: colors.backgroundBase,
                                  borderRadius: const BorderRadius.vertical(
                                    bottom: Radius.circular(Radii.lg),
                                  ),
                                  clipBehavior: Clip.antiAlias,
                                  child: Scrollbar(
                                    controller: _albumScroll,
                                    thumbVisibility: true,
                                    radius: const Radius.circular(2),
                                    child: _albumList(_switchAlbum, menu: true),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _albumList(ValueChanged<AssetPathEntity> onOpen, {bool menu = false}) {
    final folders = menu
        ? _model.albums
        : _model.albums.where((album) => !album.isAll).toList();
    if (!menu && folders.isEmpty) {
      return _DevicePickerMessage(
        message: context.strings.noAlbumsOnThisDevice,
      );
    }
    return ListView.separated(
      key: PageStorageKey(menu ? 'deviceAlbums' : 'localPickerAlbums'),
      controller: menu ? _albumScroll : null,
      shrinkWrap: menu,
      padding: menu
          ? const EdgeInsetsDirectional.fromSTEB(
              Spacing.md,
              Spacing.sm,
              Spacing.lg,
              Spacing.sm,
            )
          : const EdgeInsets.all(Spacing.md),
      itemCount: folders.length,
      separatorBuilder: (_, _) => const SizedBox(height: Spacing.sm),
      itemBuilder: (context, index) {
        final album = folders[index];
        return _DeviceAlbumRow(
          key: ValueKey(album.id),
          album: album,
          library: _model.library,
          selected: menu && album.id == _model.album?.id,
          onTap: () => onOpen(album),
        );
      },
    );
  }

  Widget _grid([SelectedFiles? selectedFiles]) {
    if (!_model.hasAccess && !_model.refreshing) {
      return _DevicePickerMessage(
        message: context.strings.devicePickerPermissionHint,
        action: context.strings.openSettings,
        onAction: () => PhotoManager.openSetting(),
      );
    }
    final limitedAccessNotice = _model.permission == PermissionState.limited
        ? Padding(
            padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
            child: MenuComponent(
              title: context.strings.devicePickerLimitedAccess,
              subtitle: context.strings.selectMorePhotos,
              trailing: const HugeIcon(
                icon: HugeIcons.strokeRoundedAdd01,
                size: IconSizes.medium,
              ),
              onTap: _manageAccess,
            ),
          )
        : null;
    if (_model.media.isEmpty) {
      if (_model.refreshing || _model.loadingMore) {
        return Center(
          child: LoadingComponent(
            semanticsLabel: context.strings.loadingYourPhotos,
          ),
        );
      }
      return _DevicePickerMessage(
        header: limitedAccessNotice,
        message: _model.error == null
            ? context.strings.noPhotosFoundHere
            : context.strings.somethingWentWrong,
        action: context.strings.retry,
        onAction: () => _model.refresh(),
      );
    }
    return DevicePickerGallery(
      model: _model,
      selectedFiles: selectedFiles,
      header: limitedAccessNotice,
      footer: Column(
        children: [
          SizedBox(
            height: selectedFiles == null
                ? MediaQuery.textScalerOf(context).scale(20) +
                      Spacing.xxl +
                      Spacing.md
                : Spacing.md,
          ),
          if (_model.loadingMore) const LoadingComponent(),
          if (_model.error != null)
            _DevicePickerMessage(
              message: context.strings.somethingWentWrong,
              action: context.strings.retry,
              onAction: _model.hasMore
                  ? _model.loadMore
                  : () => _model.refresh(),
            ),
        ],
      ),
    );
  }

  Widget _addButton(Future<void> Function() onTap) => ListenableBuilder(
    listenable: Listenable.merge([_model, _model.selectionChanges]),
    builder: (context, _) => PickerAddButton(
      label: _model.allowEmptySelection && _model.selectionCount == 0
          ? context.strings.done
          : null,
      isDisabled: !_model.canConfirm,
      onTap: onTap,
    ),
  );
}

class PickerAddButton extends StatelessWidget {
  const PickerAddButton({
    required this.isDisabled,
    required this.onTap,
    this.label,
    super.key,
  });

  final bool isDisabled;
  final Future<void> Function() onTap;
  final String? label;

  @override
  Widget build(BuildContext context) => Center(
    heightFactor: 1,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 428),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          Spacing.xl,
          Spacing.lg,
          Spacing.xl,
          Spacing.sm,
        ),
        child: ButtonComponent(
          label: label ?? context.strings.addSelected,
          isDisabled: isDisabled,
          onTap: onTap,
          shouldShowSuccessState: false,
        ),
      ),
    ),
  );
}

String _albumName(BuildContext context, AssetPathEntity? album) =>
    album == null || album.isAll ? context.strings.recent : album.name;

class _DeviceAlbumRow extends StatefulWidget {
  const _DeviceAlbumRow({
    super.key,
    required this.album,
    required this.library,
    required this.selected,
    required this.onTap,
  });
  final AssetPathEntity album;
  final DeviceMediaLibrary library;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_DeviceAlbumRow> createState() => _DeviceAlbumRowState();
}

class _DeviceAlbumRowState extends State<_DeviceAlbumRow> {
  late Future<List<AssetEntity>> _cover = widget.library.readFirstPage(
    widget.album,
    1,
  );
  late Future<int> _count = widget.library.count(widget.album);

  @override
  void didUpdateWidget(covariant _DeviceAlbumRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.album, widget.album)) {
      _cover = widget.library.readFirstPage(widget.album, 1);
      _count = widget.library.count(widget.album);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    return Semantics(
      selected: widget.selected,
      child: ThumbnailListItem(
        backgroundColor: thumbnailListItemBackgroundColor(context),
        selectedBorderColor: colors.strokeDark,
        isSelected: widget.selected,
        onTap: widget.onTap,
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(
            ThumbnailListItem.defaultLeadingRadius,
          ),
          child: FutureBuilder<List<AssetEntity>>(
            future: _cover,
            builder: (context, snapshot) => snapshot.data?.isNotEmpty == true
                ? ThumbnailWidget(
                    fileFromAsset(widget.album.name, snapshot.data!.first),
                    rawThumbnail: true,
                  )
                : ColoredBox(color: colors.fillLight),
          ),
        ),
        title: Text(
          _albumName(context, widget.album),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyles.body.copyWith(color: colors.textBase),
        ),
        subtitle: FutureBuilder<int>(
          future: _count,
          builder: (context, count) => Text(
            count.hasData ? context.strings.itemCount(count: count.data!) : '',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyles.mini.copyWith(color: colors.textLight),
          ),
        ),
        trailing: SizedBox.square(
          dimension: IconSizes.small,
          child: widget.selected
              ? const Center(child: CollectionSelectedBadge())
              : null,
        ),
      ),
    );
  }
}

class _DevicePickerBoundary extends StatefulWidget {
  const _DevicePickerBoundary({required this.position, required this.child});

  final BoundaryPosition position;
  final Widget child;

  @override
  State<_DevicePickerBoundary> createState() => _DevicePickerBoundaryState();
}

class _DevicePickerBoundaryState extends State<_DevicePickerBoundary>
    with BoundaryReporter {
  @override
  Widget build(BuildContext context) =>
      boundaryWidget(position: widget.position, child: widget.child);
}

class _DevicePickerMessage extends StatelessWidget {
  const _DevicePickerMessage({
    required this.message,
    this.action,
    this.onAction,
    this.header,
  });

  final String message;
  final String? action;
  final VoidCallback? onAction;
  final Widget? header;

  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(Spacing.xxl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ?header,
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyles.body.copyWith(
              color: context.componentColors.textLight,
            ),
          ),
          if (action != null) ...[
            const SizedBox(height: Spacing.lg),
            ButtonComponent(
              label: action!,
              onTap: onAction,
              size: ButtonComponentSize.small,
              variant: ButtonComponentVariant.secondary,
            ),
          ],
        ],
      ),
    ),
  );
}
