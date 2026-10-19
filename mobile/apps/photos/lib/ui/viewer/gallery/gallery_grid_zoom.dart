import "dart:async";
import "dart:math" as math;
import "dart:ui" as ui;

import "package:flutter/material.dart";
import "package:flutter/scheduler.dart";
import "package:logging/logging.dart";
import "package:photos/core/constants.dart";
import "package:photos/models/file/dummy_file.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/gallery/gallery_grid_zoom_layout.dart";
import "package:photos/models/gallery/gallery_groups.dart";
import "package:photos/ui/viewer/actions/select_all_status_icon.dart";
import "package:photos/ui/viewer/file/thumbnail_widget.dart";
import "package:photos/ui/viewer/gallery/component/gallery_file_widget.dart";
import "package:photos/ui/viewer/gallery/component/group/group_header_widget.dart";
import "package:photos/ui/viewer/gallery/component/group/type.dart";
import "package:photos/ui/viewer/gallery/gallery_app_bar_widget.dart";
import "package:photos/ui/viewer/gallery/gallery_pinch_detector.dart";
import "package:photos/ui/viewer/gallery/gallery_thumbnail_snapshot.dart";
import "package:photos/ui/viewer/gallery/gallery_zoom_image.dart";

class GalleryGridZoom extends StatefulWidget {
  const GalleryGridZoom({
    required this.groups,
    required this.scrollController,
    required this.sectionOrigin,
    required this.appBarHeight,
    this.trailingExtent,
    this.minimumScrollRange = 0,
    required this.pinHeaders,
    required this.enabled,
    required this.onCommit,
    required this.child,
    this.showSelectAll = false,
    this.showGallerySettingsCTA = false,
    this.groupHeaderAction,
    this.thumbnailBuilder,
    super.key,
  });

  final GalleryGroups groups;
  final ScrollController scrollController;
  final double Function() sectionOrigin;
  final double appBarHeight;
  final double Function()? trailingExtent;
  final double minimumScrollRange;
  final bool pinHeaders;
  final bool enabled;
  final Future<void> Function(int columns, double scrollOffset) onCommit;
  final bool showSelectAll;
  final bool showGallerySettingsCTA;
  final Widget? groupHeaderAction;
  final Widget Function(EnteFile)? thumbnailBuilder;
  final Widget child;

  @override
  State<GalleryGridZoom> createState() => _GalleryGridZoomState();
}

class _GalleryGridZoomState extends State<GalleryGridZoom>
    with TickerProviderStateMixin {
  static final _logger = Logger("GalleryGridZoom");
  final _snapshots = GalleryThumbnailSnapshots();
  late final _density = AnimationController.unbounded(vsync: this);
  late final _opacity = AnimationController(vsync: this, value: 1);
  late final _justifiedCatchup = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 90),
  );
  _ZoomSession? _session;
  ScrollHoldController? _hold;
  List<_ZoomItem> _items = [];
  int _lower = 0;
  int _upper = 0;
  bool _settling = false;
  bool _committing = false;
  double _requestedDensity = 3;
  double _catchupGap = 0;
  Timer? _warmupTimer;

  @override
  void initState() {
    super.initState();
    _density.addListener(_updateSegment);
    _justifiedCatchup.addListener(_applyRequestedDensity);
    widget.groups.selectedFiles?.addListener(_selectionChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _warmLayouts();
  }

  void _warmLayouts() {
    final groups = widget.groups;
    _warmupTimer?.cancel();
    _warmupTimer = Timer(const Duration(milliseconds: 350), () {
      if (!mounted ||
          widget.groups != groups ||
          !widget.enabled ||
          _session != null) {
        return;
      }
      if (SchedulerBinding.instance.transientCallbackCount > 0) {
        _warmLayouts();
        return;
      }
      unawaited(
        groups
            .prepareJustifiedZoomLayout(headerExtent: _headerExtent(groups, 2))
            .then<void>((_) {})
            .catchError((Object error, StackTrace stack) {
              _logger.warning("Could not prepare zoom layout", error, stack);
            }),
      );
      for (
        var columns = photoGridSizeMin;
        columns <= photoGridSizeMax;
        columns++
      ) {
        groups.gridZoomLayout(
          columns: columns,
          headerExtent: _headerExtent(groups, columns),
        );
      }
    });
  }

  double _headerExtent(GalleryGroups groups, int columns) =>
      groups.groupType.showGroupHeader()
      ? groups.groupHeaderExtent +
            (columns == photoGridSizeMax ? 4 : 0) -
            (groups.crossAxisCount == photoGridSizeMax ? 4 : 0)
      : GalleryGroups.spacing;

  @override
  void didUpdateWidget(GalleryGridZoom oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.groups.selectedFiles != widget.groups.selectedFiles) {
      oldWidget.groups.selectedFiles?.removeListener(_selectionChanged);
      widget.groups.selectedFiles?.addListener(_selectionChanged);
      _clear();
    }
    if (oldWidget.groups != widget.groups) _warmLayouts();
    if (!widget.enabled ||
        !identical(oldWidget.groups.allFiles, widget.groups.allFiles) ||
        oldWidget.groups.widthAvailable != widget.groups.widthAvailable ||
        (!_committing && oldWidget.groups != widget.groups)) {
      _clear();
    }
  }

  void _selectionChanged() {
    if (_session != null) setState(_clear);
  }

  void _start(Offset focalPoint) {
    if (_session != null ||
        !widget.enabled ||
        widget.scrollController.positions.length != 1) {
      return;
    }
    final box = context.findRenderObject() as RenderBox;
    final position = widget.scrollController.position;
    if (position.outOfRange) return;
    final groups = widget.groups;
    final origin = widget.sectionOrigin();
    final sourceScrollOffset = position.pixels;
    final trailingExtent = widget.trailingExtent?.call() ?? 0;
    final source = groups.gridZoomLayout(
      columns: groups.crossAxisCount,
      headerExtent: groups.groupHeaderExtent,
    );
    final point = focalPoint - Offset(0, origin);
    final anchor =
        source.tileAt(point) ??
        source
            .tilesInViewport(
              Rect.fromLTWH(
                0,
                point.dy,
                source.width,
                source.headerExtent + source.tileExtent * 2,
              ),
            )
            .firstOrNull;
    if (anchor == null || focalPoint.dy < widget.appBarHeight) return;
    _hold = position.hold(() {});
    final fraction = ((point.dy - anchor.rect.top) / anchor.rect.height).clamp(
      0.0,
      1.0,
    );
    final layouts = <int, GalleryGridZoomLayout>{};
    final offsets = <int, double>{};
    final origins = <int, double>{};
    void addLayout(GalleryGridZoomLayout layout) {
      final columns = layout.columns;
      final target = layout.tileForIndex(anchor.index)!;
      final delta =
          target.rect.top -
          anchor.rect.top +
          fraction * (target.rect.height - anchor.rect.height);
      final maxScroll = math.max(
        widget.minimumScrollRange,
        origin +
            sourceScrollOffset +
            layout.totalExtent +
            trailingExtent -
            position.viewportDimension,
      );
      final scroll =
          (sourceScrollOffset + (origin > widget.appBarHeight ? 0 : delta))
              .clamp(0.0, maxScroll);
      layouts[columns] = layout;
      offsets[columns] = scroll;
      origins[columns] = origin - (scroll - sourceScrollOffset);
    }

    for (var columns = 2; columns <= photoGridSizeMax; columns++) {
      final headerExtent = _headerExtent(groups, columns);
      final layout = columns == source.columns
          ? source
          : columns == 2
          ? groups.cachedGridZoomLayout(
              columns: columns,
              headerExtent: headerExtent,
            )
          : groups.gridZoomLayout(columns: columns, headerExtent: headerExtent);
      if (layout != null) addLayout(layout);
    }
    _requestedDensity = source.columns.toDouble();
    _density.value = source.columns.toDouble();
    _opacity.value = 1;
    final session = _session = _ZoomSession(
      initialColumns: source.columns,
      layouts: layouts,
      scrollOffsets: offsets,
      origins: origins,
      size: box.size,
      clipTop: math.max(widget.appBarHeight, origin),
      images: _snapshots.capture(),
    );
    _lower = -1;
    _updateSegment();
    if (!layouts.containsKey(2)) {
      session.justifiedReady = groups
          .prepareJustifiedZoomLayout(headerExtent: _headerExtent(groups, 2))
          .then((layout) {
            if (!mounted || _session != session) return;
            addLayout(layout);
            if (_settling) return;
            if (_density.value == photoGridSizeMin &&
                _requestedDensity < photoGridSizeMin &&
                !MediaQuery.disableAnimationsOf(context)) {
              _catchupGap = photoGridSizeMin - _requestedDensity;
              _justifiedCatchup.value = 1;
              unawaited(
                _justifiedCatchup.animateBack(0, curve: Curves.easeOutCubic),
              );
            } else {
              _applyRequestedDensity();
            }
          })
          .catchError((Object error, StackTrace stack) {
            _logger.warning("Could not prepare zoom layout", error, stack);
          });
    }
  }

  void _update(double scale, Offset focalPoint) {
    final session = _session;
    if (session == null || _settling || !scale.isFinite || scale <= 0) return;
    final densityDelta =
        session.initialColumns / scale - session.initialColumns;
    _requestedDensity = (session.initialColumns + densityDelta * 0.5).clamp(
      2.0,
      photoGridSizeMax.toDouble(),
    );
    if (_requestedDensity >= photoGridSizeMin) {
      _justifiedCatchup.stop();
      _catchupGap = 0;
    }
    _applyRequestedDensity();
  }

  void _applyRequestedDensity() {
    final session = _session;
    if (session == null || _settling) return;
    final remainingGap = math.min(
      _catchupGap * _justifiedCatchup.value,
      math.max(0.0, photoGridSizeMin - _requestedDensity),
    );
    _density.value = math.max(
      session.layouts.containsKey(2) ? 2.0 : photoGridSizeMin.toDouble(),
      _requestedDensity + remainingGap,
    );
  }

  void _updateSegment() {
    final session = _session;
    if (session == null) return;
    final lower = _density.value.floor().clamp(2, photoGridSizeMax);
    final upper = math.min(lower + 1, photoGridSizeMax);
    if (_lower == lower && _upper == upper) return;
    _lower = lower;
    _upper = upper;
    final start = session.layouts[lower]!;
    final end = session.layouts[upper]!;
    final startOrigin = session.origins[lower]!;
    final endOrigin = session.origins[upper]!;
    final viewport = Rect.fromLTRB(
      0,
      session.clipTop,
      session.size.width,
      session.size.height,
    );
    final startViewport = viewport.shift(Offset(0, -startOrigin));
    final endViewport = viewport.shift(Offset(0, -endOrigin));
    final indices = <int>{
      for (final tile in start.tilesInViewport(startViewport)) tile.index,
      for (final tile in end.tilesInViewport(endViewport)) tile.index,
    }.toList()..sort();
    final items = <_ZoomItem>[];
    for (final index in indices) {
      final first = start.tileForIndex(index)!;
      final last = end.tileForIndex(index)!;
      final from = first.rect.shift(Offset(0, startOrigin));
      final to = last.rect.shift(Offset(0, endOrigin));
      final isSelected =
          widget.groups.selectedFiles?.files.contains(first.file) ?? false;
      final item = _ZoomItem(
        key: ValueKey(("gallery-grid-zoom-tile", index)),
        from: from,
        to: to,
        fromOpacity: from.overlaps(viewport) ? 1 : 0,
        toOpacity: to.overlaps(viewport) ? 1 : 0,
        fadeDuringReflow:
            from.overlaps(viewport) &&
            to.overlaps(viewport) &&
            (from.left - to.left).abs() > (from.width + to.width) / 2,
        file: first.file,
        fileIndex: index,
        isSelected: isSelected,
      );
      items.add(item);
      if (isSelected) {
        items.add(
          _ZoomItem(
            key: ValueKey(("gallery-grid-zoom-selection", index)),
            from: Rect.fromLTWH(from.right - 20, from.top + 4, 16, 16),
            to: Rect.fromLTWH(to.right - 20, to.top + 4, 16, 16),
            fromOpacity: item.fromOpacity,
            toOpacity: item.toOpacity,
            fadeDuringReflow: item.fadeDuringReflow,
            selectionColor: galleryFileSelectionColor(
              context,
              first.file,
              widget.groups.currentUserID,
            ),
          ),
        );
      }
    }
    Map<String, ({GalleryGridZoomHeader header, Rect rect})> headers(
      GalleryGridZoomLayout layout,
      Rect visible,
      double origin,
    ) {
      final list = layout.headersInViewport(visible).toList();
      final pinned = widget.pinHeaders
          ? layout.headerAtOffset(visible.top)
          : null;
      if (pinned != null && !list.any((header) => header.id == pinned.id)) {
        list.insert(0, pinned);
      }
      return {
        for (final header in list)
          header.id: (
            header: header,
            rect: header.rect.shift(
              Offset(
                0,
                header.id == pinned?.id
                    ? math.max(origin, session.clipTop - header.rect.top)
                    : origin,
              ),
            ),
          ),
      };
    }

    final startHeaders = headers(start, startViewport, startOrigin);
    final endHeaders = headers(end, endViewport, endOrigin);
    final pinnedFrom = widget.pinHeaders
        ? start.headerAtOffset(startViewport.top)?.id
        : null;
    final pinnedTo = widget.pinHeaders
        ? end.headerAtOffset(endViewport.top)?.id
        : null;
    for (final id in {...startHeaders.keys, ...endHeaders.keys}) {
      final first = startHeaders[id];
      final last = endHeaders[id];
      final header = (first ?? last)!.header;
      final allSelected = session.headerSelections.putIfAbsent(id, () {
        final selected = widget.groups.selectedFiles?.files;
        return selected != null &&
            selected.isNotEmpty &&
            widget.groups.allFiles
                .getRange(header.firstFileIndex, header.endFileIndex)
                .where((file) => file is! DummyFile)
                .every(selected.contains);
      });
      items.add(
        _ZoomItem(
          key: ValueKey(("gallery-grid-zoom-header", id)),
          from: first?.rect ?? last!.rect,
          to: last?.rect ?? first!.rect,
          fromOpacity: first == null ? 0 : 1,
          toOpacity: last == null ? 0 : 1,
          header: header,
          isSelected: allSelected,
          pinnedFrom: id == pinnedFrom,
          pinnedTo: id == pinnedTo,
          headerActions:
              id == pinnedFrom ||
              id == pinnedTo ||
              identical(
                (first ?? last)!.header.firstFile,
                widget.groups.allFiles.first,
              ),
        ),
      );
    }
    setState(() => _items = items);
  }

  Future<void> _end(bool cancelled) async {
    final session = _session;
    if (session == null || _settling) return;
    _settling = true;
    _justifiedCatchup.stop();
    _catchupGap = 0;
    var target = cancelled ? session.initialColumns : _requestedDensity.round();
    try {
      if (target == 2 && !session.layouts.containsKey(2)) {
        await session.justifiedReady;
        if (!mounted || _session != session) return;
        if (!session.layouts.containsKey(2)) target = photoGridSizeMin;
      }
      await _density
          .animateTo(
            target.toDouble(),
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
          )
          .orCancel;
      if (!mounted || _session != session) return;
      if (target != session.initialColumns) {
        _committing = true;
        await widget.onCommit(target, session.scrollOffsets[target]!);
        if (!mounted || _session != session) return;
      }
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted || _session != session) return;
      await _opacity
          .animateTo(
            0,
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 90),
          )
          .orCancel;
    } on TickerCanceled {
      return;
    } finally {
      if (mounted && _session == session) setState(_clear);
    }
  }

  void _clear() {
    final images = _session?.images.values.toList() ?? <ui.Image>[];
    _session = null;
    _catchupGap = 0;
    _justifiedCatchup.value = 0;
    _items = [];
    _settling = false;
    _committing = false;
    _density.stop();
    _opacity.stop();
    _hold?.cancel();
    _hold = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final image in images) {
        image.dispose();
      }
    });
  }

  @override
  void dispose() {
    _warmupTimer?.cancel();
    widget.groups.selectedFiles?.removeListener(_selectionChanged);
    _clear();
    _density.dispose();
    _opacity.dispose();
    _justifiedCatchup.dispose();
    super.dispose();
  }

  Widget _buildThumbnail(_ZoomSession session, _ZoomItem item, EnteFile file) {
    final image = GalleryZoomImage(
      animation: _density,
      lower: _lower,
      from: item.from,
      to: item.to,
      image: session.images[file],
      child: session.images[file] != null
          ? const SizedBox.expand()
          : widget.thumbnailBuilder?.call(file) ??
                ThumbnailWidget(
                  file,
                  rawThumbnail: true,
                  thumbnailSize: session.initialColumns <= 3
                      ? thumbnailLargeSize
                      : thumbnailSmallSize,
                  useCachedThumbnailAsPlaceholder: true,
                ),
    );
    if (!item.isSelected) return image;
    return Stack(
      fit: StackFit.expand,
      children: [
        image,
        ColoredBox(
          key: ValueKey(("gallery-grid-zoom-selection-shade", item.fileIndex!)),
          color: const Color.fromARGB(102, 0, 0, 0),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    final background = GalleryAppBarWidget.backgroundColor(context);
    return GalleryThumbnailSnapshotScope(
      snapshots: _snapshots,
      child: GalleryPinchDetector(
        enabled: widget.enabled && !_settling,
        onStart: _start,
        onUpdate: _update,
        onEnd: (cancelled) => unawaited(_end(cancelled)),
        child: Stack(
          fit: StackFit.expand,
          children: [
            AbsorbPointer(absorbing: session != null, child: widget.child),
            if (session != null)
              Positioned.fill(
                top: session.clipTop,
                child: IgnorePointer(
                  child: ExcludeSemantics(
                    child: FadeTransition(
                      opacity: _opacity,
                      child: ColoredBox(
                        color: background,
                        child: Flow(
                          key: const ValueKey("gallery-grid-zoom-overlay"),
                          delegate: _ZoomFlowDelegate(
                            density: _density,
                            lower: _lower,
                            items: _items,
                            clipTop: session.clipTop,
                            tileExtent:
                                session.layouts[photoGridSizeMin]!.tileExtent,
                            headerExtent: widget.groups.groupHeaderExtent,
                          ),
                          children: [
                            for (final item in _items)
                              if (item.selectionColor case final color?)
                                RepaintBoundary(
                                  key: item.key,
                                  child: SelectAllStatusIcon(
                                    isSelected: true,
                                    size: 16,
                                    selectedFillColor: color,
                                    selectedTickCutsOut: true,
                                  ),
                                )
                              else if (item.file case final file?)
                                RepaintBoundary(
                                  key: item.key,
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(1),
                                    child: _buildThumbnail(session, item, file),
                                  ),
                                )
                              else
                                RepaintBoundary(
                                  key: item.key,
                                  child: ColoredBox(
                                    color: background,
                                    child: GroupHeaderWidget(
                                      title: item.header!.title(context),
                                      gridSize: session.initialColumns,
                                      filesInGroup: const [],
                                      selectedFiles: null,
                                      allSelectedOverride: item.isSelected,
                                      showSelectAll: widget.showSelectAll,
                                      showGalleryLayoutSettingCTA:
                                          item.headerActions &&
                                          widget.showGallerySettingsCTA,
                                      action: item.headerActions
                                          ? widget.groupHeaderAction
                                          : null,
                                      height: widget.groups.groupHeaderExtent,
                                    ),
                                  ),
                                ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ZoomSession {
  _ZoomSession({
    required this.initialColumns,
    required this.layouts,
    required this.scrollOffsets,
    required this.origins,
    required this.size,
    required this.clipTop,
    required this.images,
  });
  final int initialColumns;
  final Map<int, GalleryGridZoomLayout> layouts;
  final Map<int, double> scrollOffsets;
  final Map<int, double> origins;
  final Size size;
  final double clipTop;
  final Map<EnteFile, ui.Image> images;
  final Map<String, bool> headerSelections = {};
  Future<void>? justifiedReady;
}

class _ZoomItem {
  const _ZoomItem({
    required this.key,
    required this.from,
    required this.to,
    required this.fromOpacity,
    required this.toOpacity,
    this.file,
    this.fileIndex,
    this.isSelected = false,
    this.selectionColor,
    this.header,
    this.pinnedFrom = false,
    this.pinnedTo = false,
    this.headerActions = false,
    this.fadeDuringReflow = false,
  });
  final Key key;
  final Rect from;
  final Rect to;
  final double fromOpacity;
  final double toOpacity;
  final EnteFile? file;
  final int? fileIndex;
  final bool isSelected;
  final Color? selectionColor;
  final GalleryGridZoomHeader? header;
  final bool pinnedFrom;
  final bool pinnedTo;
  final bool headerActions;
  final bool fadeDuringReflow;
}

class _ZoomFlowDelegate extends FlowDelegate {
  _ZoomFlowDelegate({
    required this.density,
    required this.lower,
    required this.items,
    required this.clipTop,
    required this.tileExtent,
    required this.headerExtent,
  }) : super(repaint: density);
  final Animation<double> density;
  final int lower;
  final List<_ZoomItem> items;
  final double clipTop;
  final double tileExtent;
  final double headerExtent;

  @override
  BoxConstraints getConstraintsForChild(int i, BoxConstraints constraints) =>
      items[i].selectionColor != null
      ? const BoxConstraints.tightFor(width: 16, height: 16)
      : BoxConstraints.tight(
          Size(
            items[i].file != null ? tileExtent : constraints.maxWidth,
            items[i].file != null ? tileExtent : headerExtent,
          ),
        );

  @override
  void paintChildren(FlowPaintingContext context) {
    final progress = (density.value - lower).clamp(0.0, 1.0);
    int? pinnedIndex;
    void paint(int index) {
      final item = items[index];
      final rect = Rect.lerp(item.from, item.to, progress)!;
      final size = context.getChildSize(index)!;
      var opacity = ui.lerpDouble(item.fromOpacity, item.toOpacity, progress)!;
      if (item.fadeDuringReflow) {
        opacity *= 1 - 0.35 * 4 * progress * (1 - progress);
      }
      if (opacity == 0 ||
          rect.bottom < clipTop ||
          rect.top > context.size.height + clipTop) {
        return;
      }
      context.paintChild(
        index,
        transform: Matrix4.identity()
          ..translateByDouble(rect.left, rect.top - clipTop, 0, 1)
          ..scaleByDouble(
            rect.width / size.width,
            rect.height / size.height,
            1,
            1,
          ),
        opacity: opacity,
      );
    }

    for (var index = 0; index < items.length; index++) {
      final item = items[index];
      if (progress < 0.5 ? item.pinnedFrom : item.pinnedTo) {
        pinnedIndex = index;
      } else {
        paint(index);
      }
    }
    if (pinnedIndex != null) paint(pinnedIndex);
  }

  @override
  bool shouldRepaint(_ZoomFlowDelegate oldDelegate) =>
      oldDelegate.items != items || oldDelegate.lower != lower;

  @override
  bool shouldRelayout(_ZoomFlowDelegate oldDelegate) =>
      oldDelegate.items != items ||
      oldDelegate.tileExtent != tileExtent ||
      oldDelegate.headerExtent != headerExtent;
}
