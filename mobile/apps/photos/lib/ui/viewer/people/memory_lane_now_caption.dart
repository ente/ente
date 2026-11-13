import "package:ente_components/theme/text_styles.dart";
import "package:ente_strings/ente_strings.dart";
import "package:flutter/material.dart";
import "package:photos/theme/ente_theme.dart";

class MemoryLaneNowCaption extends StatelessWidget {
  const MemoryLaneNowCaption({required this.name, super.key});

  final String name;

  static TextStyle get textStyle => TextStyle(
    color: darkTheme.textTheme.h2Bold.color,
    fontFamily: "Gochi Hand",
    package: TextStyles.fontPackage,
    fontFamilyFallback: const [TextStyles.fontFamily],
    fontWeight: FontWeight.w400,
    fontSize: 22,
  );

  @override
  Widget build(BuildContext context) {
    const placeholder = "\uFFFC";
    final strings = context.strings;
    final caption = name.isEmpty
        ? placeholder
        : strings.memoryLaneCaptionNow(name: name, now: placeholder);
    final parts = caption.trim().split(placeholder);
    return Text.rich(
      TextSpan(
        children: [
          for (var index = 0; index < parts.length; index++) ...[
            if (index > 0)
              TextSpan(text: strings.memoryLaneNow, style: textStyle),
            TextSpan(text: parts[index]),
          ],
        ],
      ),
      style: darkTheme.textTheme.bodyMuted,
      textAlign: TextAlign.center,
      softWrap: false,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}
