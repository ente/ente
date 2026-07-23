import "package:ente_ui/components/close_icon_button.dart";
import "package:ente_ui/theme/ente_theme.dart";
import "package:flutter/material.dart";

Future<T?> showAlertBottomSheet<T>(
  BuildContext context, {
  required String title,
  required String message,
  required String assetPath,
  List<Widget>? buttons,
  bool isDismissible = true,
  bool showCloseButton = true,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    isDismissible: isDismissible,
    enableDrag: isDismissible,
    backgroundColor: Colors.transparent,
    builder: (context) => AlertBottomSheet<T>(
      title: title,
      message: message,
      assetPath: assetPath,
      buttons: buttons,
      showCloseButton: showCloseButton,
    ),
  );
}

class AlertBottomSheet<T> extends StatelessWidget {
  final String title;
  final String message;
  final String assetPath;
  final List<Widget>? buttons;
  final bool showCloseButton;

  const AlertBottomSheet({
    required this.title,
    required this.message,
    required this.assetPath,
    this.buttons,
    this.showCloseButton = true,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = getEnteColorScheme(context);
    final textTheme = getEnteTextTheme(context);

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.backgroundElevated2,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (showCloseButton)
                const Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [CloseIconButton()],
                ),
              SizedBox(height: showCloseButton ? 12 : 24),
              Center(child: Image.asset(assetPath)),
              const SizedBox(height: 20),
              Text(title, style: textTheme.h3Bold, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              Text(
                message,
                style: textTheme.body.copyWith(color: colorScheme.textMuted),
                textAlign: TextAlign.center,
              ),
              ..._buildButtonsSection(),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildButtonsSection() {
    if (buttons == null || buttons!.isEmpty) return [];

    return [
      const SizedBox(height: 20),
      ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: buttons!.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (_, index) => buttons![index],
      ),
    ];
  }
}
