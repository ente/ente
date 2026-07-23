import 'package:flutter/material.dart';
import 'package:photos/theme/ente_theme.dart';

class MenuSectionDescriptionWidget extends StatelessWidget {
  final String content;
  const MenuSectionDescriptionWidget({required this.content, super.key});

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
