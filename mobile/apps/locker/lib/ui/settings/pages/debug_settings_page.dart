import "package:ente_components/ente_components.dart";
import "package:flutter/foundation.dart";
import "package:flutter/material.dart";
import "package:hugeicons/hugeicons.dart";
import "package:locker/ui/pages/document_viewer_page.dart";
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
        if (kDebugMode) ...[
          const SizedBox(height: Spacing.sm),
          SettingsItem(
            title: "Document viewer preview",
            icon: HugeIcons.strokeRoundedFile02,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const DocumentViewerPage(
                  fileName: "Scan 30 Sep 2026, 13.11.pdf",
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
