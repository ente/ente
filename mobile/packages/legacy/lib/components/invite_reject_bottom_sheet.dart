import "package:ente_ui/components/base_bottom_sheet.dart";
import "package:ente_ui/theme/ente_theme.dart";
import "package:flutter/material.dart";

Future<T?> showEmailSheet<T>(
  BuildContext context, {
  required String email,
  required String message,
  required List<Widget> buttons,
}) {
  return showBaseBottomSheet<T>(
    context,
    title: email,
    headerSpacing: 20,
    child: EmailSheet(message: message, buttons: buttons),
  );
}

class EmailSheet extends StatelessWidget {
  final String message;
  final List<Widget> buttons;

  const EmailSheet({super.key, required this.message, required this.buttons});

  @override
  Widget build(BuildContext context) {
    final colorScheme = getEnteColorScheme(context);
    final textTheme = getEnteTextTheme(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          message,
          style: textTheme.small.copyWith(color: colorScheme.textMuted),
        ),
        const SizedBox(height: 20),
        ...buttons,
      ],
    );
  }
}
