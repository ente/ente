import 'package:flutter/material.dart';
import "package:photos/generated/l10n.dart";
import 'package:photos/theme/ente_theme.dart';
import "package:styled_text/styled_text.dart";

class SectionTitle extends StatelessWidget {
  final String? title;
  final bool mutedTitle;
  final Widget? titleWithBrand;
  final EdgeInsetsGeometry? padding;

  const SectionTitle({
    this.title,
    this.titleWithBrand,
    this.mutedTitle = false,
    super.key,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final enteTextTheme = getEnteTextTheme(context);
    Widget child;
    if (titleWithBrand != null) {
      child = titleWithBrand!;
    } else if (title != null) {
      child = Text(
        title!,
        style: mutedTitle ? enteTextTheme.bodyMuted : enteTextTheme.largeBold,
      );
    } else {
      child = const SizedBox.shrink();
    }
    return Container(
      constraints: const BoxConstraints(minHeight: 48),
      alignment: Alignment.centerLeft,
      padding: padding,
      child: child,
    );
  }
}

class SectionOptions extends StatelessWidget {
  final Widget title;
  final Widget? trailingWidget;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;

  const SectionOptions(
    this.title, {
    this.trailingWidget,
    this.padding = const EdgeInsets.only(left: 12, right: 0),
    super.key,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (trailingWidget != null) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          padding: padding,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Align(alignment: Alignment.centerLeft, child: title),
              trailingWidget!,
            ],
          ),
        ),
      );
    } else {
      return Container(
        alignment: Alignment.centerLeft,
        padding: padding,
        child: title,
      );
    }
  }
}

Widget getOnEnteSection(BuildContext context) {
  final textTheme = getEnteTextTheme(context);

  final style = TextStyle(
    fontWeight: FontWeight.w600,
    fontFamily: 'Inter',
    fontSize: 21,
    color: textTheme.largeBold.color,
  );

  return StyledText(
    text: AppLocalizations.of(context).onEnte,
    style: style,
    tags: {'branding': StyledTextTag(style: style)},
  );
}
