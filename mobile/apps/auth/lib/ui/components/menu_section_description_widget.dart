import 'package:ente_auth/theme/ente_theme.dart';
import 'package:flutter/material.dart';

class MenuSectionDescriptionWidget extends StatelessWidget {
  final String content;
  const MenuSectionDescriptionWidget({super.key, required this.content});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: Text(
        content,
        textAlign: TextAlign.left,
        style: getEnteTextTheme(
          context,
        ).mini.copyWith(color: getEnteColorScheme(context).textMuted),
      ),
    );
  }
}
