import "dart:async";
import "dart:math" as math;

import "package:ente_components/ente_components.dart";
import "package:ente_strings/ente_strings.dart";
import "package:flutter/material.dart";
import "package:flutter/rendering.dart" show ScrollDirection;
import "package:hugeicons/hugeicons.dart";
import "package:photos/ui/viewer/gallery/state/gallery_boundaries_provider.dart";

class SelectionSheetAction {
  const SelectionSheetAction({
    required this.labelText,
    required this.onTap,
    this.hugeIcon,
    this.iconWidget,
    this.shouldShow = true,
    this.isCritical = false,
    this.gridOrder,
    this.key,
  }) : assert(hugeIcon != null || iconWidget != null);

  final String labelText;
  final VoidCallback? onTap;
  final List<List<dynamic>>? hugeIcon;
  final Widget? iconWidget;
  final bool shouldShow;
  final bool isCritical;
  final int? gridOrder;
  final Key? key;
}

class SelectionActionSheet extends StatefulWidget {
  const SelectionActionSheet({
    required this.actions,
    required this.selectionControls,
    this.backgroundColor,
    super.key,
  });

  final List<SelectionSheetAction> actions;
  final Widget selectionControls;
  final Color? backgroundColor;

  @override
  State<SelectionActionSheet> createState() => _SelectionActionSheetState();
}

class _SelectionActionSheetState extends State<SelectionActionSheet> {
  final _sheetController = DraggableScrollableController();
  InheritedGalleryBoundaries? _boundaries;
  ScrollController? _galleryController;
  ValueNotifier<bool>? _galleryScrolling;
  ScrollController? _actionsController;
  double? _minHeight;
  double _minExtent = 0;
  double _maxExtent = 1;
  bool _isCollapsing = false;

  static const _duration = Motion.slow;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final boundaries = GalleryBoundariesProvider.of(context);
    if (_boundaries != boundaries) {
      _boundaries?.scrollControllerNotifier.removeListener(_bindGallery);
      _boundaries = boundaries;
      _boundaries?.scrollControllerNotifier.addListener(_bindGallery);
      _bindGallery();
    }
  }

  void _bindGallery() {
    _galleryController?.removeListener(_onGalleryScroll);
    _galleryScrolling?.removeListener(_onGalleryActivityChanged);
    _galleryController = _boundaries?.scrollControllerNotifier.value;
    _galleryController?.addListener(_onGalleryScroll);
    _galleryScrolling = _galleryController?.positions.length == 1
        ? _galleryController!.position.isScrollingNotifier
        : null;
    _galleryScrolling?.addListener(_onGalleryActivityChanged);
  }

  void _onGalleryScroll() {
    if (_isCollapsing ||
        !_sheetController.isAttached ||
        _galleryController?.positions.length != 1 ||
        _galleryController!.position.userScrollDirection ==
            ScrollDirection.idle ||
        _sheetController.size <= _minExtent + 0.001) {
      return;
    }
    _isCollapsing = true;
    unawaited(_moveTo(_minExtent));
  }

  void _onGalleryActivityChanged() {
    if (!(_galleryScrolling?.value ?? false)) _isCollapsing = false;
  }

  void _toggleSheet() {
    if (!_sheetController.isAttached) return;
    unawaited(
      _moveTo(
        _sheetController.size >= _maxExtent - 0.001 ? _minExtent : _maxExtent,
      ),
    );
  }

  Future<void> _moveTo(double extent) async {
    if (!_sheetController.isAttached) return;
    if (extent == _minExtent && (_actionsController?.hasClients ?? false)) {
      _actionsController!.jumpTo(0);
    }
    if (MediaQuery.disableAnimationsOf(context)) {
      _sheetController.jumpTo(extent);
    } else {
      await _sheetController.animateTo(
        extent,
        duration: _duration,
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _reportMinHeight(double? height) {
    _minHeight = height;
    final boundaries = _boundaries;
    if (boundaries == null ||
        boundaries.selectionSheetMinHeightNotifier.value == height) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _boundaries == boundaries) {
        boundaries.setSelectionSheetMinHeight(_minHeight);
      }
    });
  }

  @override
  void dispose() {
    _boundaries?.scrollControllerNotifier.removeListener(_bindGallery);
    _galleryController?.removeListener(_onGalleryScroll);
    _galleryScrolling?.removeListener(_onGalleryActivityChanged);
    _sheetController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final visible = widget.actions
        .where((action) => action.shouldShow)
        .toList();
    final preferred =
        visible.where((action) => action.gridOrder != null).toList()
          ..sort((a, b) => a.gridOrder!.compareTo(b.gridOrder!));
    final grid = preferred.isEmpty ? visible.take(4).toList() : preferred;
    final rows = visible.where((action) => !grid.contains(action)).toList();
    if (visible.isEmpty) {
      _reportMinHeight(null);
      return const SizedBox.shrink();
    }
    final media = MediaQuery.of(context);
    final isLandscape = media.orientation == Orientation.landscape;
    final handlePadding = EdgeInsets.only(
      top: isLandscape ? Spacing.md : Spacing.lg,
      bottom: isLandscape ? Spacing.sm : Spacing.md,
    );
    final handleHeight = handlePadding.vertical + 5;
    final controlsSpacing = isLandscape ? Spacing.xs : Spacing.sm;
    final dividerSpacing = isLandscape ? Spacing.sm : Spacing.lg;
    final gridRowSpacing = isLandscape ? Spacing.sm : Spacing.md;
    final colors = context.componentColors;
    final sheetColor = widget.backgroundColor ?? colors.fillLight;
    final miniHeight =
        media.textScaler.scale(TextStyles.mini.fontSize!) *
        TextStyles.mini.height!;
    final rowHeight = math.max(48.0, miniHeight * 2 + Spacing.lg);
    final controlsHeight = math.max(
      44.0,
      media.textScaler.scale(TextStyles.body.fontSize!) *
              TextStyles.body.height! +
          Spacing.md * 2,
    );
    final dividerHeight = dividerSpacing * 2 + 1 + Spacing.xs;
    final baseHeight =
        controlsHeight + controlsSpacing + handleHeight + media.padding.bottom;

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth - media.padding.horizontal;
        final sheetWidth = math.min(
          640.0,
          availableWidth - (isLandscape ? Spacing.lg * 2 : 0),
        );
        final minTileWidth =
            64 *
            media.textScaler.scale(TextStyles.mini.fontSize!) /
            TextStyles.mini.fontSize!;
        final gridWidth = sheetWidth - Spacing.md * 2;
        final availableColumns =
            isLandscape &&
                grid.length > 4 &&
                gridWidth >= minTileWidth * 8 + Spacing.xs * 7
            ? 8
            : gridWidth >= minTileWidth * 4 + Spacing.xs * 3
            ? 4
            : 2;
        final columns = math.min(availableColumns, grid.length);
        final gridRows = (grid.length / columns).ceil();
        final labelWidth =
            (sheetWidth - Spacing.md * 2 - Spacing.xs * (columns - 1)) /
            columns;
        var labelHeight = miniHeight;
        for (final action in grid) {
          final painter = TextPainter(
            text: TextSpan(text: action.labelText, style: TextStyles.mini),
            textDirection: Directionality.of(context),
            textScaler: media.textScaler,
            maxLines: 2,
            ellipsis: "…",
          )..layout(maxWidth: math.max(0, labelWidth));
          labelHeight = math.max(labelHeight, painter.height);
          painter.dispose();
        }
        final tileHeight = math.max(
          64.0,
          IconSizes.small + Spacing.sm * 2 + Spacing.xs * 3 + labelHeight,
        );
        final gridHeight =
            gridRows * tileHeight + (gridRows - 1) * gridRowSpacing;
        final bottomSpacing = rows.isEmpty
            ? Spacing.sm
            : isLandscape
            ? Spacing.lg
            : Spacing.xxl;
        final fullHeight =
            baseHeight +
            gridHeight +
            bottomSpacing +
            (rows.isEmpty ? 0 : dividerHeight + rows.length * rowHeight);
        final availableHeight = math.min(
          constraints.maxHeight,
          media.size.height,
        );
        final maxHeight = math.min(
          fullHeight,
          math.max(
            0.0,
            availableHeight - media.viewPadding.top - kToolbarHeight,
          ),
        );
        if (maxHeight <= controlsHeight + controlsSpacing) {
          _reportMinHeight(null);
          return const SizedBox.shrink();
        }
        final minHeight = math.min(
          baseHeight + tileHeight + Spacing.sm,
          maxHeight,
        );
        final peekHeight = math.min(
          baseHeight +
              gridHeight +
              (rows.isEmpty ? Spacing.sm : dividerHeight + rowHeight / 2),
          maxHeight,
        );
        _reportMinHeight(minHeight);
        _minExtent = minHeight / availableHeight;
        _maxExtent = maxHeight / availableHeight;
        final peekExtent = peekHeight / availableHeight;

        return SafeArea(
          top: false,
          bottom: false,
          child: Align(
            alignment: Alignment.bottomCenter,
            heightFactor: 1,
            child: SizedBox(
              width: sheetWidth,
              child: DraggableScrollableSheet(
                controller: _sheetController,
                expand: false,
                initialChildSize: peekExtent,
                minChildSize: _minExtent,
                maxChildSize: _maxExtent,
                shouldCloseOnMinExtent: false,
                snap: true,
                snapSizes: peekExtent > _minExtent && peekExtent < _maxExtent
                    ? [peekExtent]
                    : null,
                snapAnimationDuration: MediaQuery.disableAnimationsOf(context)
                    ? const Duration(milliseconds: 1)
                    : _duration,
                builder: (context, scrollController) {
                  _actionsController = scrollController;
                  return Column(
                    children: [
                      SizedBox(
                        height: controlsHeight,
                        child: widget.selectionControls,
                      ),
                      SizedBox(height: controlsSpacing),
                      Expanded(
                        child: Material(
                          color: sheetColor,
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(Radii.bottomSheet),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: SafeArea(
                            top: false,
                            child: CustomScrollView(
                              controller: scrollController,
                              slivers: [
                                SliverPersistentHeader(
                                  pinned: true,
                                  delegate: _SheetHandle(
                                    height: handleHeight,
                                    backgroundColor: sheetColor,
                                    child: Semantics(
                                      button: true,
                                      label: context.strings.more,
                                      onTap: _toggleSheet,
                                      onIncrease: () => _moveTo(_maxExtent),
                                      onDecrease: () => _moveTo(_minExtent),
                                      child: GestureDetector(
                                        behavior: HitTestBehavior.opaque,
                                        onTap: _toggleSheet,
                                        child: Padding(
                                          padding: handlePadding,
                                          child: Center(
                                            child: Container(
                                              width: 36,
                                              height: 5,
                                              decoration: BoxDecoration(
                                                color: colors.textLightest,
                                                borderRadius:
                                                    BorderRadius.circular(3),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                SliverToBoxAdapter(
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: Spacing.md,
                                    ),
                                    child: Column(
                                      spacing: gridRowSpacing,
                                      children: [
                                        for (
                                          var start = 0;
                                          start < grid.length;
                                          start += columns
                                        )
                                          Row(
                                            spacing: Spacing.xs,
                                            children: [
                                              for (final action
                                                  in grid
                                                      .skip(start)
                                                      .take(columns))
                                                Expanded(
                                                  child: _SheetAction(
                                                    key: action.key,
                                                    action: action,
                                                    height: tileHeight,
                                                  ),
                                                ),
                                              for (
                                                var i = grid
                                                    .skip(start)
                                                    .take(columns)
                                                    .length;
                                                i < columns;
                                                i++
                                              )
                                                const Expanded(
                                                  child: SizedBox.shrink(),
                                                ),
                                            ],
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                                if (rows.isNotEmpty) ...[
                                  SliverToBoxAdapter(
                                    child: DividerComponent(
                                      padding: EdgeInsets.symmetric(
                                        horizontal: Spacing.lg,
                                        vertical: dividerSpacing,
                                      ),
                                    ),
                                  ),
                                  SliverToBoxAdapter(
                                    child: ListenableBuilder(
                                      listenable: _sheetController,
                                      builder: (context, child) {
                                        final enabled =
                                            _sheetController.isAttached
                                            ? _sheetController.size >=
                                                  _maxExtent - 0.001
                                            : peekExtent >= _maxExtent;
                                        return IgnorePointer(
                                          ignoring: !enabled,
                                          child: ExcludeSemantics(
                                            excluding: !enabled,
                                            child: child,
                                          ),
                                        );
                                      },
                                      child: Padding(
                                        padding: const EdgeInsets.only(
                                          top: Spacing.xs,
                                        ),
                                        child: Column(
                                          children: [
                                            for (final action in rows)
                                              _SheetAction(
                                                key: action.key,
                                                action: action,
                                                height: rowHeight,
                                                isRow: true,
                                              ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                                SliverToBoxAdapter(
                                  child: SizedBox(height: bottomSpacing),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SheetHandle extends SliverPersistentHeaderDelegate {
  _SheetHandle({
    required this.child,
    required this.backgroundColor,
    required this.height,
  });

  final Widget child;
  final Color backgroundColor;
  final double height;

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) => ColoredBox(color: backgroundColor, child: child);

  @override
  bool shouldRebuild(covariant _SheetHandle oldDelegate) =>
      child != oldDelegate.child ||
      backgroundColor != oldDelegate.backgroundColor ||
      height != oldDelegate.height;
}

class _SheetAction extends StatelessWidget {
  const _SheetAction({
    required this.action,
    required this.height,
    this.isRow = false,
    super.key,
  });

  final SelectionSheetAction action;
  final double height;
  final bool isRow;

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    final iconColor = action.onTap == null
        ? colors.textLightest
        : action.isCritical
        ? colors.warning
        : colors.textLight;
    final textColor = action.onTap != null && isRow && !action.isCritical
        ? colors.textBase
        : iconColor;
    final icon = action.hugeIcon != null
        ? HugeIcon(
            icon: action.hugeIcon!,
            size: IconSizes.small,
            color: iconColor,
          )
        : IconTheme.merge(
            data: IconThemeData(size: IconSizes.small, color: iconColor),
            child: action.iconWidget!,
          );
    final label = Text(
      action.labelText,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      textAlign: isRow ? TextAlign.start : TextAlign.center,
      style: TextStyles.mini.copyWith(color: textColor),
    );
    return Semantics(
      button: true,
      enabled: action.onTap != null,
      child: InkWell(
        onTap: action.onTap,
        borderRadius: isRow ? null : BorderRadius.circular(Radii.md),
        child: SizedBox(
          height: height,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: isRow ? Spacing.lg : 0,
              vertical: isRow ? 0 : Spacing.xs,
            ),
            child: isRow
                ? Row(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(Spacing.sm),
                        child: icon,
                      ),
                      const SizedBox(width: Spacing.md),
                      Expanded(child: label),
                    ],
                  )
                : Column(
                    mainAxisAlignment: MainAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(Spacing.sm),
                        child: icon,
                      ),
                      const SizedBox(height: Spacing.xs),
                      label,
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
