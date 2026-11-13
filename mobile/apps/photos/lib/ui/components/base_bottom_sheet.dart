import "package:flutter/material.dart";
import "package:hugeicons/hugeicons.dart";
import "package:photos/theme/ente_theme.dart";

Future<T?> showBaseBottomSheet<T>(
  BuildContext context, {
  required String title,
  required Widget child,
  TextStyle? titleStyle,
  bool showCloseButton = true,
  VoidCallback? onClose,
  double headerSpacing = 16,
  Color? backgroundColor,
  Color? modalBackgroundColor,
  CrossAxisAlignment crossAxisAlignment = CrossAxisAlignment.start,
  EdgeInsets padding = const EdgeInsets.all(20),
  bool isDismissible = true,
  bool enableDrag = true,
  bool isKeyboardAware = true,
  double topCornerRadius = 20,
  Color? closeButtonBackgroundColor,
  double closeButtonSize = 36,
  double closeIconSize = 20,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    isDismissible: isDismissible,
    enableDrag: enableDrag,
    backgroundColor: modalBackgroundColor,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(topCornerRadius),
      ),
    ),
    clipBehavior: Clip.antiAlias,
    builder: (context) => BaseBottomSheet(
      title: title,
      titleStyle: titleStyle,
      showCloseButton: showCloseButton,
      onClose: onClose,
      headerSpacing: headerSpacing,
      backgroundColor: backgroundColor,
      crossAxisAlignment: crossAxisAlignment,
      padding: padding,
      isKeyboardAware: isKeyboardAware,
      topCornerRadius: topCornerRadius,
      closeButtonBackgroundColor: closeButtonBackgroundColor,
      closeButtonSize: closeButtonSize,
      closeIconSize: closeIconSize,
      child: child,
    ),
  );
}

class BaseBottomSheet extends StatelessWidget {
  final Widget child;
  final String title;
  final TextStyle? titleStyle;
  final bool showCloseButton;
  final VoidCallback? onClose;
  final CrossAxisAlignment crossAxisAlignment;
  final EdgeInsets padding;
  final Color? backgroundColor;
  final double headerSpacing;
  final bool isKeyboardAware;
  final double topCornerRadius;
  final Color? closeButtonBackgroundColor;
  final double closeButtonSize;
  final double closeIconSize;

  const BaseBottomSheet({
    required this.child,
    required this.title,
    this.titleStyle,
    this.showCloseButton = true,
    this.onClose,
    this.crossAxisAlignment = CrossAxisAlignment.start,
    this.padding = const EdgeInsets.all(20),
    this.backgroundColor,
    this.headerSpacing = 16,
    this.isKeyboardAware = true,
    this.topCornerRadius = 20,
    this.closeButtonBackgroundColor,
    this.closeButtonSize = 36,
    this.closeIconSize = 20,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = getEnteColorScheme(context);
    final textTheme = getEnteTextTheme(context);
    final bottomInset = isKeyboardAware
        ? MediaQuery.of(context).viewInsets.bottom
        : 0.0;

    return Container(
      decoration: BoxDecoration(
        color: backgroundColor ?? colorScheme.fill,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(topCornerRadius),
          topRight: Radius.circular(topCornerRadius),
        ),
      ),
      child: Padding(
        padding: EdgeInsets.only(bottom: bottomInset),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: padding,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: crossAxisAlignment,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(title, style: titleStyle ?? textTheme.largeBold),
                    if (showCloseButton)
                      BottomSheetCloseButton(
                        onTap: onClose,
                        backgroundColor: closeButtonBackgroundColor,
                        buttonSize: closeButtonSize,
                        iconSize: closeIconSize,
                      )
                    else
                      const SizedBox.shrink(),
                  ],
                ),
                if (headerSpacing > 0) SizedBox(height: headerSpacing),
                child,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class BottomSheetCloseButton extends StatelessWidget {
  final VoidCallback? onTap;
  final Color? backgroundColor;
  final double buttonSize;
  final double iconSize;

  const BottomSheetCloseButton({
    super.key,
    this.onTap,
    this.backgroundColor,
    this.buttonSize = 36,
    this.iconSize = 20,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = getEnteColorScheme(context);

    return GestureDetector(
      onTap: onTap ?? () => Navigator.of(context).pop(),
      child: Container(
        width: buttonSize,
        height: buttonSize,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: backgroundColor ?? colorScheme.fillDark,
        ),
        child: HugeIcon(
          icon: HugeIcons.strokeRoundedCancel01,
          size: iconSize,
          color: colorScheme.textBase,
        ),
      ),
    );
  }
}
