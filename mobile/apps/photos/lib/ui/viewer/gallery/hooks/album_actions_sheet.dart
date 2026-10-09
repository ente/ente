import "dart:math" as math;

import "package:ente_components/ente_components.dart";
import "package:flutter/gestures.dart";
import "package:flutter/material.dart";

Future<T?> showAlbumActionsSheet<T>(
  BuildContext context,
  List<EntePopupMenuOption<T>> options,
) {
  final criticalIndex = options.indexWhere(
    (option) => option.labelColor != null,
  );
  final platform = Theme.of(context).platform;
  final isMobile =
      platform == TargetPlatform.android || platform == TargetPlatform.iOS;
  Widget builder(BuildContext context) {
    final colors = context.componentColors;
    final media = MediaQuery.of(context);
    final isLandscape = media.orientation == Orientation.landscape;
    return BottomSheetComponent(
      showCloseButton: false,
      backgroundColor: colors.fillLight,
      padding: EdgeInsets.only(
        top: isLandscape ? Spacing.md : Spacing.lg,
        bottom: isLandscape ? Spacing.xs : Spacing.sm,
      ),
      content: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: media.size.height * _maxHeightFraction,
        ),
        child: SingleChildScrollView(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final gridWidth = constraints.maxWidth - Spacing.md * 2;
              final minTileWidth =
                  64 *
                  media.textScaler.scale(TextStyles.mini.fontSize!) /
                  TextStyles.mini.fontSize!;
              final columns = gridWidth >= minTileWidth * 4 + Spacing.xs * 3
                  ? 4
                  : 2;
              final tiles = [
                ...options
                    .where((option) => option.labelColor == null)
                    .take(criticalIndex == -1 ? columns : columns - 1),
                if (criticalIndex != -1) options[criticalIndex],
              ];
              final rows = options
                  .where((option) => !tiles.contains(option))
                  .toList();
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 36,
                    height: 5,
                    decoration: BoxDecoration(
                      color: colors.textLightest,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  SizedBox(height: isLandscape ? Spacing.sm : Spacing.md),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: Spacing.xs,
                      children: [
                        for (final option in tiles)
                          Expanded(
                            child: _AlbumActionTile(
                              option: option,
                              onTap: () =>
                                  Navigator.of(context).pop(option.value),
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (rows.isNotEmpty)
                    DividerComponent(
                      padding: EdgeInsets.symmetric(
                        horizontal: Spacing.lg,
                        vertical: isLandscape ? Spacing.sm : Spacing.lg,
                      ),
                    ),
                  for (final option in rows)
                    _AlbumActionRow(
                      option: option,
                      onTap: () => Navigator.of(context).pop(option.value),
                    ),
                  const SizedBox(height: Spacing.sm),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  if (!isMobile) {
    return showBottomSheetComponent<T>(
      context: context,
      barrierColor: context.componentColors.specialScrim.withValues(alpha: 0.4),
      builder: builder,
    );
  }
  return Navigator.of(
    context,
  ).push(_AlbumActionsSheetRoute<T>(context, builder: builder));
}

class _AlbumActionsSheetRoute<T> extends ModalBottomSheetRoute<T> {
  _AlbumActionsSheetRoute(BuildContext context, {required super.builder})
    : _capturedThemes = InheritedTheme.capture(
        from: context,
        to: Navigator.of(context).context,
      ),
      super(
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Colors.transparent,
        modalBarrierColor: context.componentColors.specialScrim.withValues(
          alpha: 0.4,
        ),
        barrierLabel: MaterialLocalizations.of(context).scrimLabel,
        barrierOnTapHint: MaterialLocalizations.of(
          context,
        ).scrimOnTapHint(MaterialLocalizations.of(context).bottomSheetLabel),
      );

  final CapturedThemes _capturedThemes;
  final _pointerOrigins = <int, Offset>{};
  int? _dismissPointer;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return _capturedThemes.wrap(
      DisplayFeatureSubScreen(
        anchorPoint: anchorPoint,
        child: Builder(
          builder: (context) {
            final media = MediaQuery.of(context);
            final theme = Theme.of(context);
            final availableWidth =
                media.size.width -
                media.padding.horizontal -
                (media.orientation == Orientation.landscape
                    ? Spacing.lg * 2
                    : 0);
            final width = math.min(640.0, availableWidth);
            return Theme(
              data: theme.copyWith(
                bottomSheetTheme: theme.bottomSheetTheme.copyWith(
                  constraints: BoxConstraints.tightFor(width: width),
                ),
              ),
              child: super.buildPage(context, animation, secondaryAnimation),
            );
          },
        ),
      ),
    );
  }

  void _dismiss() {
    if (isCurrent) navigator!.pop();
  }

  void _endPointer(PointerEvent event) {
    _pointerOrigins.remove(event.pointer);
    if (event.pointer == _dismissPointer && isActive) {
      if (isCurrent) {
        navigator!.pop();
      } else {
        controller!.stop();
        navigator!.removeRoute(this);
      }
    }
  }

  @override
  Widget buildModalBarrier() {
    final gestureSettings = MediaQuery.gestureSettingsOf(navigator!.context);
    return BlockSemantics(
      child: Semantics(
        label: barrierLabel,
        onTapHint: barrierOnTapHint,
        onTap: _dismiss,
        onDismiss: _dismiss,
        child: Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (event) =>
              _pointerOrigins[event.pointer] = event.position,
          onPointerMove: (event) {
            final origin = _pointerOrigins[event.pointer];
            if (origin == null || !isCurrent || _dismissPointer != null) return;
            final delta = event.position - origin;
            if (delta.distance > computeHitSlop(event.kind, gestureSettings)) {
              _dismissPointer = event.pointer;
              controller!.reverse();
            }
          },
          onPointerUp: _endPointer,
          onPointerCancel: _endPointer,
          onPointerSignal: (event) {
            if (event is PointerScrollEvent) _dismiss();
          },
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: _dismiss,
            onLongPress: _dismiss,
            excludeFromSemantics: true,
            child: ExcludeSemantics(
              child: IgnorePointer(child: super.buildModalBarrier()),
            ),
          ),
        ),
      ),
    );
  }
}

class _AlbumActionTile<T> extends StatelessWidget {
  const _AlbumActionTile({required this.option, required this.onTap});

  final EntePopupMenuOption<T> option;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    final foreground = option.labelColor ?? colors.textLight;
    return Semantics(
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Radii.md),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 64),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                SizedBox.square(
                  dimension: 34,
                  child: Center(
                    child: IconTheme.merge(
                      data: IconThemeData(
                        color: foreground,
                        size: IconSizes.small,
                      ),
                      child: option.leadingWidget ?? const SizedBox.shrink(),
                    ),
                  ),
                ),
                const SizedBox(height: Spacing.xs),
                Text(
                  option.label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyles.mini.copyWith(color: foreground),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AlbumActionRow<T> extends StatelessWidget {
  const _AlbumActionRow({required this.option, required this.onTap});

  final EntePopupMenuOption<T> option;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;

    return Semantics(
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
            child: Row(
              spacing: Spacing.md,
              children: [
                SizedBox.square(
                  dimension: 34,
                  child: Center(
                    child: IconTheme.merge(
                      data: IconThemeData(
                        color: option.labelColor ?? colors.textLight,
                        size: IconSizes.small,
                      ),
                      child: option.leadingWidget ?? const SizedBox.shrink(),
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    option.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyles.mini.copyWith(
                      color: option.labelColor ?? colors.textBase,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

const _maxHeightFraction = 0.8;
