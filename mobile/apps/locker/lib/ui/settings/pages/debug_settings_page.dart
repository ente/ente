import "package:ente_components/ente_components.dart";
import "package:flutter/material.dart";
import "package:hugeicons/hugeicons.dart";
import "package:locker/services/feature_flag_service.dart";
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
        const SizedBox(height: Spacing.sm),
        SettingsItem(
          title: "Disable internal user",
          icon: HugeIcons.strokeRoundedUserBlock01,
          showChevron: false,
          trailing: ToggleSwitchComponent.async(
            value: () => FeatureFlagService.instance.isInternalUserDisabled,
            onChanged: () =>
                FeatureFlagService.instance.setInternalUserDisabled(
                  !FeatureFlagService.instance.isInternalUserDisabled,
                ),
          ),
        ),
      ],
    );
  }
}
