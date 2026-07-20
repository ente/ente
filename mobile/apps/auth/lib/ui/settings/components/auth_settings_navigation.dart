import 'package:flutter/material.dart';

Future<void> pushAuthSettingsPage(BuildContext context, Widget page) async {
  await Navigator.of(
    context,
  ).push<void>(MaterialPageRoute<void>(builder: (_) => page));
}
