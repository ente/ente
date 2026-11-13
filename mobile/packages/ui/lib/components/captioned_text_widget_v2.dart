import 'package:ente_ui/theme/ente_theme.dart';
import 'package:flutter/material.dart';

class CaptionedTextWidgetV2 extends StatelessWidget {
  final String title;
  final String? subTitle;
  final TextStyle? textStyle;
  final bool makeTextBold;
  final Color? textColor;
  final Color? subTitleColor;
  final TextStyle? subTitleTextStyle;
  final Widget? trailingTitleWidget;
  final double trailingTitleGap;
  final bool subTitleInNewLine;

  const CaptionedTextWidgetV2({
    required this.title,
    this.subTitle,
    this.textStyle,
    this.makeTextBold = false,
    this.textColor,
    this.subTitleColor,
    this.subTitleTextStyle,
    this.trailingTitleWidget,
    this.trailingTitleGap = 8.0,
    this.subTitleInNewLine = false,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final enteColorScheme = getEnteColorScheme(context);
    final enteTextTheme = getEnteTextTheme(context);

    final titleStyle =
        textStyle ??
        (makeTextBold
            ? enteTextTheme.bodyBold.copyWith(color: textColor)
            : enteTextTheme.body.copyWith(color: textColor));

    return Flexible(
      child: Padding(
        padding: EdgeInsets.symmetric(
          vertical: subTitleInNewLine ? 0 : 8,
          horizontal: 2,
        ),
        child: subTitleInNewLine
            ? Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          title,
                          style: titleStyle,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (trailingTitleWidget != null) ...[
                        SizedBox(width: trailingTitleGap),
                        trailingTitleWidget!,
                      ],
                    ],
                  ),
                  if (subTitle != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      subTitle!,
                      style:
                          subTitleTextStyle ??
                          enteTextTheme.mini.copyWith(
                            color: subTitleColor ?? enteColorScheme.textMuted,
                          ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              )
            : Row(
                children: [
                  Flexible(
                    child: trailingTitleWidget != null
                        ? Text(
                            title,
                            style: titleStyle,
                            overflow: TextOverflow.ellipsis,
                          )
                        : RichText(
                            text: TextSpan(
                              style: titleStyle,
                              children: [
                                TextSpan(text: title),
                                if (subTitle != null)
                                  TextSpan(
                                    text: ' \u2022 $subTitle',
                                    style: enteTextTheme.small.copyWith(
                                      color:
                                          subTitleColor ??
                                          enteColorScheme.textMuted,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                  ),
                  if (trailingTitleWidget != null) ...[
                    SizedBox(width: trailingTitleGap),
                    trailingTitleWidget!,
                  ],
                ],
              ),
      ),
    );
  }
}
