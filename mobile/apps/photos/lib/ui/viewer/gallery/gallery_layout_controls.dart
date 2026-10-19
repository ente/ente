import "package:ente_components/ente_components.dart";
import "package:ente_strings/ente_strings.dart";
import "package:flutter/material.dart";
import "package:flutter/rendering.dart";
import "package:photos/core/constants.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/events/gallery_layout_changed_event.dart";
import "package:photos/service_locator.dart";
import "package:photos/settings/local_settings.dart";
import "package:photos/ui/viewer/gallery/component/group/type.dart";

class GalleryLayoutControls extends StatefulWidget {
  const GalleryLayoutControls({
    super.key,
    this.showHeading = false,
    this.keepHeight = false,
  });

  final bool showHeading;
  final bool keepHeight;

  @override
  State<GalleryLayoutControls> createState() => _GalleryLayoutControlsState();
}

class _GalleryLayoutControlsState extends State<GalleryLayoutControls> {
  late GalleryLayoutType _layoutType;
  late int _gridSize;
  late GroupType _groupType;

  @override
  void initState() {
    super.initState();
    _layoutType = localSettings.getGalleryLayoutType();
    _gridSize = localSettings.getPhotoGridSize();
    _groupType = localSettings.getGalleryGroupType();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.strings;
    final colors = context.componentColors;
    final density = MenuGroupComponent(
      items: [
        MenuComponent(
          title: l10n.photosPerRow,
          trailing: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(color: colors.strokeFaint),
              borderRadius: BorderRadius.circular(Radii.md),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButtonComponent(
                  key: const ValueKey("fewer-photos-per-row"),
                  icon: const Icon(Icons.remove),
                  size: 44,
                  iconSize: 20,
                  tooltip: _gridSize > photoGridSizeMin
                      ? "${l10n.photosPerRow}: ${_gridSize - 1}"
                      : null,
                  shouldSurfaceExecutionStates: false,
                  onTap: _gridSize > photoGridSizeMin
                      ? () => _setGridSize(_gridSize - 1)
                      : null,
                ),
                SizedBox(
                  width: 28,
                  child: Center(
                    child: Text(
                      "$_gridSize",
                      style: TextStyles.bodyBold.copyWith(
                        color: colors.textBase,
                      ),
                    ),
                  ),
                ),
                IconButtonComponent(
                  key: const ValueKey("more-photos-per-row"),
                  icon: const Icon(Icons.add),
                  size: 44,
                  iconSize: 20,
                  tooltip: _gridSize < photoGridSizeMax
                      ? "${l10n.photosPerRow}: ${_gridSize + 1}"
                      : null,
                  shouldSurfaceExecutionStates: false,
                  onTap: _gridSize < photoGridSizeMax
                      ? () => _setGridSize(_gridSize + 1)
                      : null,
                ),
              ],
            ),
          ),
        ),
      ],
    );
    final grouping = MenuGroupComponent(
      items: [
        MenuComponent(
          title: l10n.groupBy,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _groupType.getLocalizedName(context),
                style: TextStyles.mini.copyWith(color: colors.textLight),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right, color: colors.textLighter, size: 20),
            ],
          ),
          onTap: _showGrouping,
        ),
      ],
    );
    final collapsed = _layoutType == GalleryLayoutType.justified ? 1.0 : 0.0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.showHeading)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              l10n.layout,
              style: TextStyles.body.copyWith(color: colors.textBase),
            ),
          ),
        Row(
          children: [
            Expanded(child: _layoutCard(GalleryLayoutType.grid)),
            const SizedBox(width: 8),
            Expanded(child: _layoutCard(GalleryLayoutType.justified)),
          ],
        ),
        if (widget.keepHeight)
          TweenAnimationBuilder<double>(
            tween: Tween(begin: collapsed, end: collapsed),
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
            builder: (context, progress, _) => _FixedHeightLayoutRows(
              collapseProgress: progress,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: ExcludeSemantics(
                    excluding: _layoutType == GalleryLayoutType.justified,
                    child: ExcludeFocus(
                      excluding: _layoutType == GalleryLayoutType.justified,
                      child: IgnorePointer(
                        ignoring: _layoutType == GalleryLayoutType.justified,
                        child: Opacity(opacity: 1 - progress, child: density),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: grouping,
                ),
              ],
            ),
          )
        else ...[
          if (_layoutType == GalleryLayoutType.grid) ...[
            const SizedBox(height: 8),
            density,
          ],
          const SizedBox(height: 8),
          grouping,
        ],
      ],
    );
  }

  Widget _layoutCard(GalleryLayoutType type) {
    final colors = context.componentColors;
    final selected = _layoutType == type;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(Radii.lg),
      side: BorderSide(
        color: selected ? colors.strokeDark : Colors.transparent,
      ),
    );
    return Semantics(
      key: ValueKey(type),
      label: type == GalleryLayoutType.grid
          ? context.strings.squarePhotos
          : context.strings.photosInOriginalProportions,
      button: true,
      selected: selected,
      onTap: () => _setLayout(type),
      child: ExcludeSemantics(
        child: Material(
          color: colors.fillLight,
          shape: shape,
          clipBehavior: Clip.antiAlias,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _setLayout(type),
            child: SizedBox(
              height: 92,
              child: Stack(
                children: [
                  Center(
                    child: SizedBox.square(
                      dimension: 52,
                      child: CustomPaint(
                        painter: _GallerySamplePainter(
                          type,
                          colors.textLighter,
                        ),
                      ),
                    ),
                  ),
                  if (selected)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: SizedBox.square(
                        dimension: 20,
                        child: Center(
                          child: Icon(
                            Icons.check,
                            color: colors.textBase,
                            size: 20,
                          ),
                        ),
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

  Future<void> _setLayout(GalleryLayoutType type) async {
    if (_layoutType == type) return;
    await localSettings.setGalleryLayoutType(type);
    if (mounted) setState(() => _layoutType = type);
    Bus.instance.fire(GalleryLayoutChangedEvent());
  }

  Future<void> _setGridSize(int size) async {
    await localSettings.setPhotoGridSize(size);
    if (mounted) setState(() => _gridSize = size);
    Bus.instance.fire(GalleryLayoutChangedEvent());
  }

  Future<void> _showGrouping() async {
    await showBottomSheetComponent<void>(
      context: context,
      builder: (sheetContext) => BottomSheetComponent(
        title: sheetContext.strings.groupBy,
        content: MenuGroupComponent(
          items: [
            for (final type in GroupType.values.where(
              (type) => type != GroupType.size && type != GroupType.none,
            ))
              MenuComponent(
                title: type.getLocalizedName(sheetContext),
                trailing: _groupType == type
                    ? Icon(
                        Icons.check,
                        color: sheetContext.componentColors.textBase,
                      )
                    : null,
                onTap: () async {
                  if (_groupType != type) {
                    await localSettings.setGalleryGroupType(type);
                    if (mounted) setState(() => _groupType = type);
                    Bus.instance.fire(GalleryLayoutChangedEvent());
                  }
                  if (sheetContext.mounted) Navigator.of(sheetContext).pop();
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _FixedHeightLayoutRows extends MultiChildRenderObjectWidget {
  const _FixedHeightLayoutRows({
    required this.collapseProgress,
    required super.children,
  });

  final double collapseProgress;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderFixedHeightLayoutRows(
        collapseProgress: collapseProgress,
        textDirection: Directionality.of(context),
      );

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderFixedHeightLayoutRows renderObject,
  ) {
    renderObject
      ..collapseProgress = collapseProgress
      ..textDirection = Directionality.of(context);
  }
}

class _RenderFixedHeightLayoutRows extends RenderFlex {
  _RenderFixedHeightLayoutRows({
    required double collapseProgress,
    required super.textDirection,
  }) : _collapseProgress = collapseProgress,
       super(
         direction: Axis.vertical,
         mainAxisSize: MainAxisSize.min,
         crossAxisAlignment: CrossAxisAlignment.stretch,
       );

  double _collapseProgress;

  set collapseProgress(double value) {
    if (_collapseProgress == value) return;
    _collapseProgress = value;
    markNeedsLayout();
  }

  @override
  void performLayout() {
    super.performLayout();
    final density = firstChild;
    if (density == null) return;
    final grouping = childAfter(density);
    if (grouping == null) return;
    final parentData = grouping.parentData! as FlexParentData;
    parentData.offset -= Offset(0, density.size.height * _collapseProgress);
  }
}

class _GallerySamplePainter extends CustomPainter {
  const _GallerySamplePainter(this.type, this.color);

  final GalleryLayoutType type;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final rect = (Offset.zero & size).deflate(0.75);
    final outline = RRect.fromRectAndRadius(rect, const Radius.circular(4));
    canvas.save();
    canvas.clipRRect(outline);
    if (type == GalleryLayoutType.grid) {
      for (var index = 1; index < 3; index++) {
        final x = rect.left + rect.width * index / 3;
        final y = rect.top + rect.height * index / 3;
        canvas.drawLine(Offset(x, rect.top), Offset(x, rect.bottom), paint);
        canvas.drawLine(Offset(rect.left, y), Offset(rect.right, y), paint);
      }
    } else {
      final y = rect.top + rect.height * 1.25 / 2.25;
      final topX = rect.left + rect.width * 1.6 / 2.6;
      final bottomX = rect.left + rect.width / 2.6;
      canvas.drawLine(Offset(rect.left, y), Offset(rect.right, y), paint);
      canvas.drawLine(Offset(topX, rect.top), Offset(topX, y), paint);
      canvas.drawLine(Offset(bottomX, y), Offset(bottomX, rect.bottom), paint);
    }
    canvas.restore();
    canvas.drawRRect(outline, paint);
  }

  @override
  bool shouldRepaint(_GallerySamplePainter oldDelegate) =>
      oldDelegate.type != type || oldDelegate.color != color;
}
