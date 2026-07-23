import "package:flutter/material.dart";
import "package:photos/theme/ente_theme.dart";

///https://www.figma.com/file/SYtMyLBs5SAOkTbfMMzhqt/ente-Visual-Design?node-id=11379%3A67490&t=VI5KulbW3HMM5MVz-4

class EmptyStateItemWidget extends StatelessWidget {
  final String textContent;
  const EmptyStateItemWidget(this.textContent, {super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = getEnteColorScheme(context);
    final textTheme = getEnteTextTheme(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.check_outlined, size: 17, color: colorScheme.strokeFaint),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            textContent,
            style: textTheme.small.copyWith(color: colorScheme.textFaint),
          ),
        ),
      ],
    );
  }
}
