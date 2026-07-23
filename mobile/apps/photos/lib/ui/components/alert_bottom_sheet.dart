import "package:flutter/material.dart";
import "package:photos/theme/ente_theme.dart";
import "package:photos/ui/components/base_bottom_sheet.dart";

Future<T?> showAlertBottomSheet<T>(
  BuildContext context, {
  required String title,
  required String message,
  String? assetPath,
  List<Widget>? buttons,
  bool isDismissible = true,
  bool showCloseButton = true,
  VoidCallback? onClose,
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
      onClose: onClose,
    ),
  );
}

class AlertBottomSheet<T> extends StatelessWidget {
  final String title;
  final String message;
  final String? assetPath;
  final List<Widget>? buttons;
  final bool showCloseButton;
  final VoidCallback? onClose;

  const AlertBottomSheet({
    required this.title,
    required this.message,
    this.assetPath,
    this.buttons,
    this.showCloseButton = true,
    this.onClose,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = getEnteColorScheme(context);
    final textTheme = getEnteTextTheme(context);

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.backgroundColour,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (showCloseButton)
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    BottomSheetCloseButton(
                      onTap: onClose,
                      backgroundColor: colorScheme.fill,
                      iconSize: 18,
                    ),
                  ],
                ),
              if (showCloseButton) const SizedBox(height: 4),
              if (assetPath != null) ...[
                Center(
                  child: FittedBox(
                    alignment: Alignment.bottomCenter,
                    fit: BoxFit.scaleDown,
                    child: Image.asset(assetPath!),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              Text(
                title,
                style: textTheme.largeBold,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text(
                message,
                style: textTheme.small.copyWith(
                  color: colorScheme.contentLight,
                ),
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
      const SizedBox(height: 24),
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
