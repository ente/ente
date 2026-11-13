import "package:flutter/material.dart";
import "package:photos/theme/ente_theme.dart";
import "package:photos/ui/components/base_bottom_sheet.dart";

Future<T?> showEmailActionSheet<T>(
  BuildContext context, {
  required String email,
  required String message,
  required List<Widget> buttons,
  String? title,
}) {
  return showBaseBottomSheet<T>(
    context,
    title: title ?? email,
    headerSpacing: 20,
    padding: const EdgeInsets.all(16),
    backgroundColor: getEnteColorScheme(context).backgroundColour,
    child: EmailActionSheetContent(message: message, buttons: buttons),
  );
}

class EmailActionSheetContent extends StatelessWidget {
  final String message;
  final List<Widget> buttons;

  const EmailActionSheetContent({
    required this.message,
    required this.buttons,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = getEnteTextTheme(context);
    final colorScheme = getEnteColorScheme(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          message,
          style: textTheme.small.copyWith(color: colorScheme.textMuted),
        ),
        const SizedBox(height: 20),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: buttons.length,
          separatorBuilder: (_, _) => const SizedBox(height: 12),
          itemBuilder: (_, index) => buttons[index],
        ),
      ],
    );
  }
}
