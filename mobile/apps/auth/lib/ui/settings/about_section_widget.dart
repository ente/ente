import 'package:ente_auth/l10n/l10n.dart';
import 'package:ente_auth/services/update_service.dart';
import 'package:ente_auth/theme/ente_theme.dart';
import 'package:ente_auth/ui/components/captioned_text_widget.dart';
import 'package:ente_auth/ui/components/expandable_menu_item_widget.dart';
import 'package:ente_auth/ui/components/menu_item_widget.dart';
import 'package:ente_auth/ui/settings/app_update_dialog.dart';
import 'package:ente_auth/ui/settings/common_settings.dart';
import 'package:ente_auth/utils/dialog_util.dart';
import 'package:ente_auth/utils/platform_util.dart';
import 'package:ente_auth/utils/toast_util.dart';
import 'package:flutter/material.dart';

class AboutSectionWidget extends StatelessWidget {
  const AboutSectionWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return ExpandableMenuItemWidget(
      title: context.l10n.about,
      selectionOptionsWidget: _getSectionOptions(context),
      leadingIcon: Icons.info_outline,
    );
  }

  Widget _getSectionOptions(BuildContext context) {
    return Column(
      children: [
        sectionOptionSpacing,
        MenuItemWidget(
          captionedTextWidget: CaptionedTextWidget(
            title: context.l10n.weAreOpenSource,
          ),
          pressedColor: getEnteColorScheme(context).fillFaint,
          trailingIcon: Icons.chevron_right_outlined,
          trailingIconIsMuted: true,
          onTap: () async {
            await PlatformUtil.openUrlInBrowser("https://github.com/ente/ente");
          },
        ),
        sectionOptionSpacing,
        AboutMenuItemWidget(
          title: context.l10n.privacy,
          url: "https://ente.com/privacy",
        ),
        sectionOptionSpacing,
        AboutMenuItemWidget(
          title: context.l10n.termsOfServicesTitle,
          url: "https://ente.com/terms",
        ),
        sectionOptionSpacing,
        UpdateService.instance.supportsInAppUpdates()
            ? Column(
                children: [
                  MenuItemWidget(
                    captionedTextWidget: CaptionedTextWidget(
                      title: context.l10n.checkForUpdates,
                    ),
                    pressedColor: getEnteColorScheme(context).fillFaint,
                    trailingIcon: Icons.chevron_right_outlined,
                    trailingIconIsMuted: true,
                    onTap: () async {
                      final dialog = createProgressDialog(
                        context,
                        context.l10n.checking,
                      );
                      await dialog.show();
                      final shouldUpdate = await UpdateService.instance
                          .shouldUpdate();
                      await dialog.hide();
                      if (shouldUpdate) {
                        if (!context.mounted) return;
                        // ignore: unawaited_futures
                        showDialog(
                          context: context,
                          builder: (BuildContext context) {
                            return AppUpdateDialog(
                              UpdateService.instance.getLatestVersionInfo(),
                            );
                          },
                          barrierColor: Colors.black.withValues(alpha: 0.85),
                        );
                      } else {
                        if (!context.mounted) return;
                        showShortToast(
                          context,
                          context.l10n.youAreOnTheLatestVersion,
                        );
                      }
                    },
                  ),
                  sectionOptionSpacing,
                ],
              )
            : const SizedBox.shrink(),
      ],
    );
  }
}

class AboutMenuItemWidget extends StatelessWidget {
  final String title;
  final String url;
  final String? webPageTitle;
  const AboutMenuItemWidget({
    required this.title,
    required this.url,
    this.webPageTitle,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return MenuItemWidget(
      captionedTextWidget: CaptionedTextWidget(title: title),
      pressedColor: getEnteColorScheme(context).fillFaint,
      trailingIcon: Icons.chevron_right_outlined,
      trailingIconIsMuted: true,
      onTap: () async {
        await PlatformUtil.openUrlInBrowser(url);
      },
    );
  }
}
