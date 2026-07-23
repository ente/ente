import 'dart:ui';

import 'package:ente_ui/components/buttons/button_widget.dart';
import 'package:ente_ui/components/buttons/models/button_result.dart';
import 'package:ente_ui/components/components_constants.dart';
import 'package:ente_ui/components/separators.dart';
import 'package:ente_ui/theme/colors.dart';
import 'package:ente_ui/theme/effects.dart';
import 'package:ente_ui/theme/ente_theme.dart';
import 'package:flutter/material.dart';
import 'package:modal_bottom_sheet/modal_bottom_sheet.dart';

enum ActionSheetType { defaultActionSheet, iconOnly }

///Returns null if dismissed
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
  return showMaterialModalBottomSheet(
    backgroundColor: Colors.transparent,
    barrierColor: backdropFaintDark,
    useRootNavigator: true,
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
  final String? title;
  final Widget? bodyWidget;
  final String? body;
  final String? bodyHighlight;
  final List<ButtonWidget> actionButtons;
  final ActionSheetType actionSheetType;
  final bool isCheckIconGreen;

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

  @override
  Widget build(BuildContext context) {
    final isTitleAndBodyNull =
        title == null && bodyWidget == null && body == null;
    final blur = MediaQuery.of(context).platformBrightness == Brightness.light
        ? blurMuted
        : blurBase;
    final extraWidth = MediaQuery.of(context).size.width - restrictedMaxWidth;
    final double? horizontalPadding = extraWidth > 0 ? extraWidth / 2 : null;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        horizontalPadding ?? 12,
        12,
        horizontalPadding ?? 12,
        32,
      ),
      child: Container(
        decoration: BoxDecoration(boxShadow: shadowMenuLight),
        child: ClipRRect(
          borderRadius: const BorderRadius.all(Radius.circular(8)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
            child: Container(
              color: backdropMutedDark,
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  24,
                  24,
                  24,
                  isTitleAndBodyNull ? 24 : 28,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    isTitleAndBodyNull
                        ? const SizedBox.shrink()
                        : Padding(
                            padding: const EdgeInsets.only(bottom: 36),
                            child: ContentContainerWidget(
                              title: title,
                              bodyWidget: bodyWidget,
                              body: body,
                              bodyHighlight: bodyHighlight,
                              actionSheetType: actionSheetType,
                              isCheckIconGreen: isCheckIconGreen,
                            ),
                          ),
                    ActionButtons(actionButtons),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class ContentContainerWidget extends StatelessWidget {
  final String? title;
  final Widget? bodyWidget;
  final String? body;
  final String? bodyHighlight;
  final ActionSheetType actionSheetType;
  final bool isCheckIconGreen;

  const ContentContainerWidget({
    required this.actionSheetType,
    required this.isCheckIconGreen,
    this.title,
    this.bodyWidget,
    this.body,
    this.bodyHighlight,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = getEnteTextTheme(context);
    final bool bodyMissing = body == null && bodyWidget == null;
    debugPrint("body missing $bodyMissing");
    return Column(
      mainAxisSize: MainAxisSize.min,
      //todo: set cross axis to center when icon should be shown in place of body
      crossAxisAlignment: actionSheetType == ActionSheetType.defaultActionSheet
          ? CrossAxisAlignment.stretch
          : CrossAxisAlignment.center,
      children: [
        title == null
            ? const SizedBox.shrink()
            : Text(
                title!,
                style: textTheme.largeBold.copyWith(
                  color: textBaseDark,
                ), //constant color
              ),
        title == null || bodyMissing
            ? const SizedBox.shrink()
            : const SizedBox(height: 19),
        actionSheetType == ActionSheetType.defaultActionSheet
            ? bodyMissing
                  ? const SizedBox.shrink()
                  : (bodyWidget != null
                        ? bodyWidget!
                        : Text(
                            body!,
                            style: textTheme.body.copyWith(
                              color: textMutedDark,
                            ), //constant color
                          ))
            : Icon(
                Icons.check_outlined,
                size: 48,
                color: isCheckIconGreen
                    ? getEnteColorScheme(context).primary700
                    : strokeBaseDark,
              ),
        actionSheetType == ActionSheetType.defaultActionSheet &&
                bodyHighlight != null
            ? Padding(
                padding: const EdgeInsets.only(top: 19.0),
                child: Text(
                  bodyHighlight!,
                  style: textTheme.body.copyWith(
                    color: textBaseDark,
                  ), //constant color
                ),
              )
            : const SizedBox.shrink(),
      ],
    );
  }
}

class ActionButtons extends StatelessWidget {
  final List<Widget> actionButtons;
  const ActionButtons(this.actionButtons, {super.key});

  @override
  Widget build(BuildContext context) {
    final actionButtonsWithSeparators = actionButtons;
    return Column(
      children:
          //Separator height is 8pts in figma. -2pts here as the action
          //buttons are 2pts extra in height in code compared to figma because
          //of the border(1pt top + 1pt bottom) of action buttons.
          addSeparators(actionButtonsWithSeparators, const SizedBox(height: 6)),
    );
  }
}
