import "package:ente_components/ente_components.dart";
import "package:flutter/material.dart";
import "package:hugeicons/hugeicons.dart";
import "package:locker/ui/settings/widgets/change_log_sheet.dart";

class DebugSettingsPage extends StatelessWidget {
  const DebugSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return SettingsPageScaffold(
      title: "Debug",
      children: [
        SettingsItem(
          title: "Show change log",
          icon: HugeIcons.strokeRoundedInformationCircle,
          onTap: () => showChangeLogSheet(context),
        ),
      ],
    );
  }
}
