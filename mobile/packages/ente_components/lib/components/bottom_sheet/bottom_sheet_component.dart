import 'dart:async';

import 'package:ente_components/components/buttons/icon_button_component.dart';
import 'package:ente_components/theme/icon_sizes.dart';
import 'package:ente_components/theme/radii.dart';
import 'package:ente_components/theme/spacing.dart';
import 'package:ente_components/theme/text_styles.dart';
import 'package:ente_components/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

/// Figma: https://www.figma.com/design/BuBNPPytxlVnqfmCUW0mgz/Ente-Visual-Design?node-id=4809-7992&m=dev
/// Section: Bottom sheet / Bottom Sheet Header
/// Specs: H2 title, optional 36px circular close action, and optional centered
/// illustration for warning and error sheets.
class _BottomSheetHeaderComponent extends StatelessWidget {
  const _BottomSheetHeaderComponent({
    this.title,
    this.illustration,
    this.onClose,
    this.closeResult,
    this.showCloseButton = true,
    this.closeTooltip = 'Close',
    this.textAlign,
    this.isCentered = false,
  });

  final String? title;
  final Widget? illustration;

  /// Called when the close button is pressed, before the sheet is dismissed.
  ///
  /// Barrier taps, drag dismissals, and system back dismissals do not call this.
  final FutureOr<void> Function()? onClose;
  final Object? closeResult;
  final bool showCloseButton;
  final String closeTooltip;
  final TextAlign? textAlign;
  final bool isCentered;

  @override
  Widget build(BuildContext context) {
    if (isCentered || illustration != null) {
      return _CenteredHeader(
        title: title,
        illustration: illustration,
        onClose: onClose,
        closeResult: closeResult,
        showCloseButton: showCloseButton,
        closeTooltip: closeTooltip,
      );
    }

    if (title == null) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (showCloseButton)
            _BottomSheetCloseButton(
              onClose: onClose,
              closeResult: closeResult,
              tooltip: closeTooltip,
            ),
        ],
      );
    }

    final colors = context.componentColors;

    return SizedBox(
      height: _headerHeight,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Text(
              title!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: textAlign,
              style: TextStyles.h2.copyWith(color: colors.textBase),
            ),
          ),
          if (showCloseButton) const SizedBox(width: Spacing.md),
          if (showCloseButton)
            _BottomSheetCloseButton(
              onClose: onClose,
              closeResult: closeResult,
              tooltip: closeTooltip,
            ),
        ],
      ),
    );
  }
}

/// Figma: https://www.figma.com/design/BuBNPPytxlVnqfmCUW0mgz/Ente-Visual-Design?node-id=4809-8027&m=dev
/// Section: Bottom sheet / Bottom sheet template
/// Specs: 20px top radius, 20px padding, 16px content gap, stacked 12px
/// action gap.
class BottomSheetComponent extends StatelessWidget {
  const BottomSheetComponent({
    super.key,
    this.title,
    this.header,
    this.message,
    this.illustration,
    this.content,
    this.actions = const [],
    this.onClose,
    this.closeResult,
    this.showCloseButton = true,
    this.closeTooltip = 'Close',
    this.textAlign,
    this.crossAxisAlignment = CrossAxisAlignment.start,
    this.padding = const EdgeInsets.all(Spacing.xl),
    this.contentSpacing = Spacing.lg,
    this.actionsTopSpacing,
    this.backgroundColor,
    this.isKeyboardAware = false,
    this.isScrollable = false,
    this.initialChildSize = 0.5,
    this.snap = false,
    this.snapSizes,
  });

  final String? title;
  final Widget? header;
  final String? message;
  final Widget? illustration;
  final Widget? content;
  final List<Widget> actions;

  /// Called when the close button is pressed, before the sheet is dismissed.
  ///
  /// Barrier taps, drag dismissals, and system back dismissals do not call this.
  final FutureOr<void> Function()? onClose;
  final Object? closeResult;
  final bool showCloseButton;
  final String closeTooltip;
  final TextAlign? textAlign;
  final CrossAxisAlignment crossAxisAlignment;
  final EdgeInsets padding;
  final double contentSpacing;
  final double? actionsTopSpacing;
  final Color? backgroundColor;
  final bool isKeyboardAware;
  final bool isScrollable;

  /// Initial sheet height fraction when [isScrollable] is true.
  final double initialChildSize;

  /// Whether the sheet snaps to [snapSizes] when [isScrollable] is true.
  final bool snap;

  /// Sheet height fractions to snap to when [isScrollable] and [snap] are true.
  final List<double>? snapSizes;

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    final bottomInset = isKeyboardAware
        ? MediaQuery.viewInsetsOf(context).bottom
        : 0.0;

    final usesCenteredLayout =
        illustration != null || (message != null && content == null);

    final effectiveHeader =
        header ??
        ((title != null || showCloseButton || usesCenteredLayout)
            ? _BottomSheetHeaderComponent(
                title: title,
                illustration: illustration,
                onClose: onClose,
                closeResult: closeResult,
                showCloseButton: showCloseButton,
                closeTooltip: closeTooltip,
                textAlign: textAlign,
                isCentered: usesCenteredLayout,
              )
            : null);

    final effectiveContent =
        content ??
        (message == null
            ? null
            : Text(
                message!,
                textAlign: usesCenteredLayout ? TextAlign.center : textAlign,
                style: TextStyles.body.copyWith(color: colors.textLight),
              ));

    final effectiveCrossAxisAlignment = usesCenteredLayout
        ? CrossAxisAlignment.stretch
        : crossAxisAlignment;

    final effectiveContentSpacing = usesCenteredLayout
        ? Spacing.lg
        : contentSpacing;

    final effectiveActionsTopSpacing =
        actionsTopSpacing ?? (usesCenteredLayout ? Spacing.xxl : Spacing.lg);

    final children = <Widget>[
      ?effectiveHeader,
      if (effectiveContent != null) ...[
        if (effectiveHeader != null) SizedBox(height: effectiveContentSpacing),
        effectiveContent,
      ],
      if (actions.isNotEmpty) ...[
        SizedBox(height: effectiveActionsTopSpacing),
        _BottomSheetActions(actions: actions),
      ],
    ];

    final sheetBody = isScrollable
        ? DraggableScrollableSheet(
            expand: false,
            initialChildSize: initialChildSize,
            snap: snap,
            snapSizes: snapSizes,
            builder: (context, scrollController) {
              return ListView(
                controller: scrollController,
                padding: padding,
                shrinkWrap: true,
                children: children,
              );
            },
          )
        : Padding(
            padding: padding,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: effectiveCrossAxisAlignment,
              children: children,
            ),
          );

    return AnimatedPadding(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: backgroundColor ?? colors.backgroundBase,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(Radii.bottomSheet),
            topRight: Radius.circular(Radii.bottomSheet),
          ),
        ),
        child: SafeArea(top: false, child: sheetBody),
      ),
    );
  }
}

/// Shows [BottomSheetComponent] with the modal behavior used by the component
/// catalog and mobile apps.
Future<T?> showBottomSheetComponent<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isDismissible = true,
  bool enableDrag = true,
  bool useRootNavigator = false,
  Color? barrierColor,
}) {
  final colors = context.componentColors;

  return showModalBottomSheet<T>(
    context: context,
    useRootNavigator: useRootNavigator,
    isScrollControlled: true,
    isDismissible: isDismissible,
    enableDrag: enableDrag,
    backgroundColor: Colors.transparent,
    barrierColor: barrierColor ?? colors.specialScrim.withValues(alpha: 0.55),
    useSafeArea: true,
    builder: (context) {
      return PopScope(canPop: isDismissible, child: builder(context));
    },
  );
}

class _CenteredHeader extends StatelessWidget {
  const _CenteredHeader({
    required this.title,
    required this.illustration,
    required this.onClose,
    required this.closeResult,
    required this.showCloseButton,
    required this.closeTooltip,
  });

  final String? title;
  final Widget? illustration;
  final FutureOr<void> Function()? onClose;
  final Object? closeResult;
  final bool showCloseButton;
  final String closeTooltip;

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            if (showCloseButton)
              _BottomSheetCloseButton(
                onClose: onClose,
                closeResult: closeResult,
                tooltip: closeTooltip,
              ),
          ],
        ),
        if (showCloseButton && (illustration != null || title != null))
          const SizedBox(height: Spacing.xs),
        if (illustration != null)
          _BottomSheetIllustration(child: illustration!),
        if (title != null) ...[
          SizedBox(height: illustration == null ? 0 : Spacing.lg),
          Text(
            title!,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyles.h2.copyWith(color: colors.textBase),
          ),
        ],
      ],
    );
  }
}

class _BottomSheetIllustration extends StatelessWidget {
  const _BottomSheetIllustration({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.only(bottom: _illustrationSlotBottomInset),
        child: FittedBox(
          alignment: Alignment.bottomCenter,
          fit: BoxFit.scaleDown,
          child: child,
        ),
      ),
    );
  }
}

class _BottomSheetCloseButton extends StatelessWidget {
  const _BottomSheetCloseButton({
    required this.onClose,
    required this.closeResult,
    required this.tooltip,
  });

  /// Called when the close button is pressed, before the sheet is dismissed.
  final FutureOr<void> Function()? onClose;
  final Object? closeResult;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return IconButtonComponent(
      tooltip: tooltip,
      variant: IconButtonComponentVariant.circular,
      shouldSurfaceExecutionStates: false,
      icon: const HugeIcon(
        icon: HugeIcons.strokeRoundedCancel01,
        size: IconSizes.small,
      ),
      onTap: () => _handleClose(context),
    );
  }

  Future<void> _handleClose(BuildContext context) async {
    await Future.sync(onClose ?? () {});
    if (!context.mounted) {
      return;
    }

    final route = ModalRoute.of(context);
    if (route == null || route.isCurrent) {
      Navigator.of(context).pop(closeResult);
    }
  }
}

class _BottomSheetActions extends StatelessWidget {
  const _BottomSheetActions({required this.actions});

  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < actions.length; index++) ...[
          actions[index],
          if (index != actions.length - 1) const SizedBox(height: Spacing.md),
        ],
      ],
    );
  }
}

const double _headerHeight = 38;
const double _illustrationSlotBottomInset = 11;
