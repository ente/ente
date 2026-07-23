import 'package:flutter/material.dart';

class SettingsSectionTitle extends StatelessWidget {
  final String title;
  final Color? color;

  const SettingsSectionTitle(this.title, {super.key, this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Padding(padding: EdgeInsets.all(4)),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            title,
            style: color != null
                ? Theme.of(
                    context,
                  ).textTheme.titleLarge!.merge(TextStyle(color: color))
                : Theme.of(context).textTheme.titleLarge,
          ),
        ),
        const Padding(padding: EdgeInsets.all(4)),
      ],
    );
  }
}
