import "package:ente_ui/components/close_icon_button.dart";
import "package:ente_ui/theme/ente_theme.dart";
import "package:flutter/material.dart";

Future<T?> showBaseBottomSheet<T>(
  BuildContext context, {
  required String title,
  required Widget child,
  bool showCloseButton = true,
  VoidCallback? onClose,
  double headerSpacing = 0,
  Color? backgroundColor,
  CrossAxisAlignment crossAxisAlignment = CrossAxisAlignment.start,
  EdgeInsets padding = const EdgeInsets.all(16),
  BorderRadiusGeometry borderRadius = const BorderRadius.only(
    topLeft: Radius.circular(24),
    topRight: Radius.circular(24),
  ),
  BoxBorder? border,
  TextStyle? titleTextStyle,
  bool isDismissible = true,
  bool enableDrag = true,
  bool isKeyboardAware = false,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    isDismissible: isDismissible,
    enableDrag: enableDrag,
    builder: (context) => BaseBottomSheet(
      title: title,
      showCloseButton: showCloseButton,
      onClose: onClose,
      headerSpacing: headerSpacing,
      backgroundColor: backgroundColor,
      crossAxisAlignment: crossAxisAlignment,
      padding: padding,
      borderRadius: borderRadius,
      border: border,
      titleTextStyle: titleTextStyle,
      isKeyboardAware: isKeyboardAware,
      child: child,
    ),
  );
}

class BaseBottomSheet extends StatelessWidget {
  final Widget child;
  final String title;
  final bool showCloseButton;
  final VoidCallback? onClose;
  final CrossAxisAlignment crossAxisAlignment;
  final EdgeInsets padding;
  final BorderRadiusGeometry borderRadius;
  final BoxBorder? border;
  final TextStyle? titleTextStyle;
  final Color? backgroundColor;
  final double headerSpacing;
  final bool isKeyboardAware;

  const BaseBottomSheet({
    required this.child,
    required this.title,
    this.showCloseButton = true,
    this.onClose,
    this.crossAxisAlignment = CrossAxisAlignment.start,
    this.padding = const EdgeInsets.all(16),
    this.borderRadius = const BorderRadius.only(
      topLeft: Radius.circular(24),
      topRight: Radius.circular(24),
    ),
    this.border,
    this.titleTextStyle,
    this.backgroundColor,
    this.headerSpacing = 0,
    this.isKeyboardAware = false,
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
        color: backgroundColor ?? colorScheme.backgroundElevated2,
        borderRadius: borderRadius,
        border: border,
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
                    Text(title, style: titleTextStyle ?? textTheme.largeBold),
                    if (showCloseButton)
                      CloseIconButton(onTap: onClose)
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
