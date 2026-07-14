import 'package:ente_auth/core/constants.dart';
import 'package:ente_auth/l10n/l10n.dart';
import 'package:ente_auth/theme/ente_theme.dart';
import 'package:ente_auth/ui/components/captioned_text_widget.dart';
import 'package:ente_auth/ui/components/expandable_menu_item_widget.dart';
import 'package:ente_auth/ui/components/menu_item_widget.dart';
import 'package:ente_auth/ui/settings/common_settings.dart';
import 'package:ente_auth/utils/email_util.dart';
import 'package:ente_auth/utils/platform_util.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:url_launcher/url_launcher.dart';

class SupportSectionWidget extends StatefulWidget {
  const SupportSectionWidget({super.key});

  @override
  State<SupportSectionWidget> createState() => _SupportSectionWidgetState();
}

class _SupportSectionWidgetState extends State<SupportSectionWidget> {
  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return ExpandableMenuItemWidget(
      title: l10n.support,
      selectionOptionsWidget: _getSectionOptions(context),
      leadingIcon: Icons.help_outline_outlined,
    );
  }

  Widget _getSectionOptions(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      children: [
        sectionOptionSpacing,
        MenuItemWidget(
          captionedTextWidget: CaptionedTextWidget(title: l10n.faq),
          pressedColor: getEnteColorScheme(context).fillFaint,
          trailingIcon: Icons.chevron_right_outlined,
          trailingIconIsMuted: true,
          onTap: () async {
            try {
              await PlatformUtil.openUrlInBrowser(
                "https://ente.com/help/auth/faq",
              );
            } catch (e) {
              Logger("SupportSection").severe("Failed to open FAQ", e);
            }
          },
        ),
        sectionOptionSpacing,
        MenuItemWidget(
          captionedTextWidget: CaptionedTextWidget(title: l10n.suggestFeatures),
          pressedColor: getEnteColorScheme(context).fillFaint,
          trailingIcon: Icons.chevron_right_outlined,
          trailingIconIsMuted: true,
          onTap: () async {
            final launched = await launchUrl(
              githubFeatureRequestUri,
              mode: LaunchMode.externalApplication,
            );
            if (!launched) {
              Logger(
                "SupportSection",
              ).warning("Failed to open feature request discussions");
            }
          },
        ),
        sectionOptionSpacing,
        // MenuItemWidget(
        //   captionedTextWidget: CaptionedTextWidget(
        //     title: l10n.email,
        //   ),
        //   pressedColor: getEnteColorScheme(context).fillFaint,
        //   trailingIcon: Icons.chevron_right_outlined,
        //   trailingIconIsMuted: true,
        //   onTap: () async {
        //     await sendEmail(context, to: supportEmail);
        //   },
        // ),
        // sectionOptionSpacing,
        MenuItemWidget(
          captionedTextWidget: CaptionedTextWidget(title: l10n.reportABug),
          pressedColor: getEnteColorScheme(context).fillFaint,
          trailingIcon: Icons.chevron_right_outlined,
          trailingIconIsMuted: true,
          onTap: () async {
            await sendLogs(context, l10n.reportBug);
          },
          onDoubleTap: () async {
            try {
              if (!context.mounted) return;
              final zipFilePath = await getZippedLogsFile(context);
              if (!context.mounted) return;
              await shareLogs(context, "auth@ente.com", zipFilePath);
            } catch (e) {
              Logger("SupportSectionWidget").severe("failed to export logs", e);
            }
          },
        ),
        sectionOptionSpacing,
      ],
    );
  }
}
