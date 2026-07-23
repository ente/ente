import 'dart:io';

import 'package:ente_auth/l10n/l10n.dart';
import 'package:ente_auth/ui/components/buttons/button_component_adapter.dart';
import 'package:ente_auth/ui/components/buttons/button_widget.dart';
import 'package:ente_auth/ui/components/models/button_result.dart';
import 'package:ente_components/ente_components.dart';
import 'package:flutter/material.dart';
import 'package:modal_bottom_sheet/modal_bottom_sheet.dart';

enum ActionSheetType { defaultActionSheet, iconOnly }

/// Compatibility adapter for legacy Auth action sheets.
///
/// Existing callers keep their [ButtonWidget] result contract while the sheet
/// renders through Ente components. New surfaces should use
/// [BottomSheetComponent] directly.
Future<ButtonResult?> showActionSheet({
  required BuildContext context,
  required List<ButtonWidget> buttons,
  ActionSheetType actionSheetType = ActionSheetType.defaultActionSheet,
  bool enableDrag = true,
  bool isDismissible = true,
  bool isCheckIconGreen = false,
  String? title,
  Widget? bodyWidget,
  String? body,
  String? bodyHighlight,
}) {
  final colors = context.componentColors;
  return showMaterialModalBottomSheet<ButtonResult>(
    backgroundColor: Colors.transparent,
    barrierColor: colors.specialScrim.withValues(alpha: 0.55),
    useRootNavigator: Platform.isIOS,
    context: context,
    isDismissible: isDismissible,
    enableDrag: enableDrag,
    builder: (_) {
      return ActionSheetWidget(
        title: title,
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

class ActionSheetWidget extends StatelessWidget {
  const ActionSheetWidget({
    required this.actionButtons,
    required this.actionSheetType,
    required this.isCheckIconGreen,
    this.title,
    this.bodyWidget,
    this.body,
    this.bodyHighlight,
    super.key,
  });

  final String? title;
  final Widget? bodyWidget;
  final String? body;
  final String? bodyHighlight;
  final List<ButtonWidget> actionButtons;
  final ActionSheetType actionSheetType;
  final bool isCheckIconGreen;

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
    final buttons = LegacySheetButtonConfiguration.from(context, actionButtons);
    final illustration = actionSheetType == ActionSheetType.iconOnly
        ? Icon(
            Icons.check_outlined,
            size: 48,
            color: isCheckIconGreen ? colors.primary : colors.iconColor,
          )
        : null;

    return BottomSheetComponent(
      title: title,
      illustration: illustration,
      content: hasDefaultContent
          ? _ActionSheetContent(
              bodyWidget: bodyWidget,
              body: body,
              bodyHighlight: bodyHighlight,
            )
          : null,
      actions: buttons.actions,
      showCloseButton: buttons.showCloseButton,
      closeTooltip: context.l10n.close,
      closeResult: buttons.closeResult,
      onClose: buttons.onClose(context),
      actionsTopSpacing: hasContent ? Spacing.lg : 0,
    );
  }
}

class _ActionSheetContent extends StatelessWidget {
  const _ActionSheetContent({this.bodyWidget, this.body, this.bodyHighlight});

  final Widget? bodyWidget;
  final String? body;
  final String? bodyHighlight;

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    final hasBody = body != null || bodyWidget != null;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (hasBody)
          bodyWidget ??
              Text(
                body!,
                style: TextStyles.body.copyWith(color: colors.textLight),
              ),
        if (bodyHighlight != null) ...[
          if (hasBody) const SizedBox(height: Spacing.lg),
          Text(
            bodyHighlight!,
            style: TextStyles.body.copyWith(color: colors.textBase),
          ),
        ],
      ],
    );
  }
}
