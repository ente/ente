import "package:ente_ui/theme/ente_theme.dart";
import 'package:flutter/widgets.dart';

class MenuSectionTitle extends StatelessWidget {
  final String title;
  final IconData? iconData;
  final EdgeInsetsGeometry padding;
  final TextStyle? textStyle;

  const MenuSectionTitle({
    super.key,
    required this.title,
    this.iconData,
    this.padding = const EdgeInsets.only(left: 8, top: 6, bottom: 6),
    this.textStyle,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = getEnteColorScheme(context);
    final effectiveTextStyle =
        textStyle ??
        getEnteTextTheme(context).small.copyWith(color: colorScheme.textMuted);
    return Padding(
      padding: padding,
      child: Row(
        children: [
          iconData != null
              ? Icon(iconData, color: colorScheme.strokeMuted, size: 17)
              : const SizedBox.shrink(),
          iconData != null ? const SizedBox(width: 8) : const SizedBox.shrink(),
          Text(title, style: effectiveTextStyle),
        ],
      ),
    );
  }
}
