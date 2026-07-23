import "dart:io";

import "package:ente_components/ente_components.dart";
import 'package:flutter/material.dart';
import 'package:modal_bottom_sheet/modal_bottom_sheet.dart';
import "package:photos/generated/l10n.dart";
import 'package:photos/models/button_result.dart';
import 'package:photos/ui/components/buttons/button_component_adapter.dart';
import 'package:photos/ui/components/buttons/button_widget.dart';

enum ActionSheetType { defaultActionSheet, iconOnly }

/// Compatibility adapter for legacy Photos action sheets.
///
/// Preserves existing [ButtonWidget]/[ButtonResult] behavior while rendering
/// through [BottomSheetComponent]. Prefer [BottomSheetComponent] directly for
/// new sheets.
Future<ButtonResult?> showActionSheet({
  required BuildContext context,
  required List<ButtonWidget> buttons,
  ActionSheetType actionSheetType = ActionSheetType.defaultActionSheet,
  bool enableDrag = true,
  bool isDismissible = true,
  bool isCheckIconGreen = false,
  String? title,
  Widget? illustration,
  Widget? bodyWidget,
  String? body,
  String? bodyHighlight,
}) {
  final colors = context.componentColors;
  return showMaterialModalBottomSheet(
    backgroundColor: Colors.transparent,
    barrierColor: colors.specialScrim.withValues(alpha: 0.55),
    // On iOS setting it to false causes previous page to shift
    // So we're explicitly setting it to true
    useRootNavigator: Platform.isIOS,
    context: context,
    isDismissible: isDismissible,
    enableDrag: enableDrag,
    builder: (_) {
      return LegacyActionSheetWidget(
        title: title,
        illustration: illustration,
        bodyWidget: bodyWidget,
        body: body,
        bodyHighlight: bodyHighlight,
        actionButtons: buttons,
        actionSheetType: actionSheetType,
        isCheckIconGreen: isCheckIconGreen,
      );
    },
  );
}

class LegacyActionSheetWidget extends StatelessWidget {
  final String? title;
  final Widget? illustration;
  final Widget? bodyWidget;
  final String? body;
  final String? bodyHighlight;
  final List<ButtonWidget> actionButtons;
  final ActionSheetType actionSheetType;
  final bool isCheckIconGreen;

  const LegacyActionSheetWidget({
    required this.actionButtons,
    required this.actionSheetType,
    required this.isCheckIconGreen,
    this.title,
    this.illustration,
    this.bodyWidget,
    this.body,
    this.bodyHighlight,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final hasDefaultContent =
        actionSheetType == ActionSheetType.defaultActionSheet &&
        (bodyWidget != null || body != null || bodyHighlight != null);
    final hasContent =
        title != null ||
        hasDefaultContent ||
        actionSheetType == ActionSheetType.iconOnly;
    final colors = context.componentColors;
    final cancelButtonIndex = sheetCancelButtonIndex(context, actionButtons);
    final cancelButton = cancelButtonIndex == -1
        ? null
        : actionButtons[cancelButtonIndex];
    final visibleButtons = [
      for (var index = 0; index < actionButtons.length; index++)
        if (index != cancelButtonIndex) actionButtons[index],
    ];
    final effectiveIllustration =
        illustration ??
        (actionSheetType == ActionSheetType.iconOnly
            ? Icon(
                Icons.check_outlined,
                size: 48,
                color: isCheckIconGreen ? colors.primary : colors.iconColor,
              )
            : null);

    return BottomSheetComponent(
      title: title,
      illustration: effectiveIllustration,
      content: hasDefaultContent
          ? _LegacyActionSheetContent(
              bodyWidget: bodyWidget,
              body: body,
              bodyHighlight: bodyHighlight,
              textAlign: illustration == null ? null : TextAlign.center,
            )
          : null,
      actions: [
        for (final button in visibleButtons)
          ButtonComponentAdapter(button: button),
      ],
      showCloseButton: cancelButton != null,
      closeTooltip: AppLocalizations.of(context).close,
      closeResult: cancelButton == null ? null : sheetCloseResult(cancelButton),
      onClose: cancelButton == null
          ? null
          : () => sheetCloseAction(context, cancelButton),
      actionsTopSpacing: illustration != null
          ? null
          : hasContent
          ? Spacing.lg
          : 0,
    );
  }
}

class _LegacyActionSheetContent extends StatelessWidget {
  final Widget? bodyWidget;
  final String? body;
  final String? bodyHighlight;
  final TextAlign? textAlign;

  const _LegacyActionSheetContent({
    this.bodyWidget,
    this.body,
    this.bodyHighlight,
    this.textAlign,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    final hasBody = body != null || bodyWidget != null;

    if (!hasBody && bodyHighlight == null) {
      return const SizedBox.shrink();
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (hasBody)
          bodyWidget ??
              Text(
                body!,
                textAlign: textAlign,
                style: TextStyles.body.copyWith(color: colors.textLight),
              ),
        if (bodyHighlight != null) ...[
          if (hasBody) const SizedBox(height: Spacing.lg),
          Text(
            bodyHighlight!,
            textAlign: textAlign,
            style: TextStyles.body.copyWith(color: colors.textBase),
          ),
        ],
      ],
    );
  }
}
