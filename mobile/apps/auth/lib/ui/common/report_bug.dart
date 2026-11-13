import 'package:ente_auth/utils/email_util.dart';
import 'package:flutter/material.dart';

PopupMenuButton<dynamic> reportBugPopupMenu(BuildContext context) {
  return PopupMenuButton(
    itemBuilder: (context) {
      final List<PopupMenuItem> items = [];
      items.add(
        const PopupMenuItem(
          value: 1,
          child: Row(children: [Text("Contact support")]),
        ),
      );
      return items;
    },
    onSelected: (value) async {
      if (value == 1) {
        await sendLogs(context, "Contact support", postShare: () {});
      }
    },
  );
}
