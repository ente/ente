import 'package:flutter/widgets.dart';
import 'package:photos/theme/ente_theme.dart';

class MenuSectionTitle extends StatelessWidget {
  final String title;
  final IconData? iconData;

  const MenuSectionTitle({super.key, required this.title, this.iconData});

  @override
  Widget build(BuildContext context) {
    final colorScheme = getEnteColorScheme(context);
    return Padding(
      padding: const EdgeInsets.only(left: 8, top: 6, bottom: 6),
      child: Row(
        children: [
          iconData != null
              ? Icon(iconData, color: colorScheme.strokeMuted, size: 17)
              : const SizedBox.shrink(),
          iconData != null ? const SizedBox(width: 8) : const SizedBox.shrink(),
          Text(
            title,
            style: getEnteTextTheme(
              context,
            ).small.copyWith(color: colorScheme.textMuted),
          ),
        ],
      ),
    );
  }
}
