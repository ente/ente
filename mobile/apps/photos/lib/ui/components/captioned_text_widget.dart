import 'package:ente_pure_utils/ente_pure_utils.dart';
import 'package:flutter/material.dart';
import 'package:photos/ente_theme_data.dart';

class CaptionedTextWidget extends StatelessWidget {
  final String title;
  final String? subTitle;
  final TextStyle? textStyle;
  final bool makeTextBold;
  final Color? textColor;
  final Color? subTitleColor;
  const CaptionedTextWidget({
    required this.title,
    this.subTitle,
    this.textStyle,
    this.makeTextBold = false,
    this.textColor,
    this.subTitleColor,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final enteColorScheme = Theme.of(context).colorScheme.enteTheme.colorScheme;
    final enteTextTheme = Theme.of(context).colorScheme.enteTheme.textTheme;

    final titleForDisplay = title.contains("@")
        ? title
        : title.capitalizeFirst();

    final List<Widget> children = [
      Flexible(
        child: Text(
          titleForDisplay,
          style:
              textStyle ??
              (makeTextBold
                  ? enteTextTheme.bodyBold.copyWith(color: textColor)
                  : enteTextTheme.body.copyWith(color: textColor)),
        ),
      ),
    ];
    if (subTitle != null) {
      children.add(const SizedBox(width: 4));
      children.add(
        Text(
          '\u2022',
          style: enteTextTheme.small.copyWith(
            color: subTitleColor ?? enteColorScheme.textMuted,
          ),
        ),
      );
      children.add(const SizedBox(width: 4));
      children.add(
        Text(
          subTitle!,
          style: enteTextTheme.small.copyWith(
            color: subTitleColor ?? enteColorScheme.textMuted,
          ),
        ),
      );
    }
    return Flexible(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 2),
        child: Row(children: children),
      ),
    );
  }
}
