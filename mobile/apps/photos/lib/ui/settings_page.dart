import "package:ente_components/ente_components.dart";
import "package:ente_lock_screen/local_authentication_service.dart";
import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:flutter/foundation.dart";
import "package:flutter/material.dart";
import "package:hugeicons/hugeicons.dart";
import "package:log_viewer/log_viewer.dart";
import "package:photos/core/configuration.dart";
import "package:photos/emergency/emergency_page.dart";
import "package:photos/generated/l10n.dart";
import "package:photos/models/user_details.dart";
import "package:photos/service_locator.dart";
import "package:photos/services/account/user_service.dart";
import "package:photos/ui/account/email_entry_page.dart";
import "package:photos/ui/account/login_page.dart";
import "package:photos/ui/components/banners/offline_settings_banner.dart";
import "package:photos/ui/components/settings/social_icons_row.dart";
import "package:photos/ui/growth/referral_screen.dart";
import "package:photos/ui/notification/toast.dart";
import "package:photos/ui/settings/about/about_us_page.dart";
import "package:photos/ui/settings/account/account_settings_page.dart";
import "package:photos/ui/settings/app_version_widget.dart";
import "package:photos/ui/settings/appearance/appearance_settings_page.dart";
import "package:photos/ui/settings/backup/backup_settings_page.dart";
import "package:photos/ui/settings/backup/free_space_options.dart";
import "package:photos/ui/settings/cast/cast_settings_page.dart";
import "package:photos/ui/settings/components/settings_item.dart";
import "package:photos/ui/settings/components/settings_page_scaffold.dart";
import "package:photos/ui/settings/debug/debug_settings_page.dart";
import "package:photos/ui/settings/debug/ml_debug_settings_page.dart";
import "package:photos/ui/settings/inherited_settings_state.dart";
import "package:photos/ui/settings/memories_settings_screen.dart";
import "package:photos/ui/settings/ml/machine_learning_settings_page.dart";
import "package:photos/ui/settings/notification_settings_screen.dart";
import "package:photos/ui/settings/search/settings_search_page.dart";
import "package:photos/ui/settings/security/security_settings_page.dart";
import "package:photos/ui/settings/storage_card_widget.dart";
import "package:photos/ui/settings/streaming/video_streaming_settings_page.dart";
import "package:photos/ui/settings/support/help_support_page.dart";
import "package:photos/ui/settings/widget_settings_screen.dart";
import "package:photos/ui/sharing/verify_identity_dialog.dart";
import "package:photos/utils/dialog_util.dart";
import "package:url_launcher/url_launcher_string.dart";

class SettingsPage extends StatelessWidget {
  final ValueNotifier<String?> emailNotifier;

  const SettingsPage({super.key, required this.emailNotifier});

  @override
  Widget build(BuildContext context) {
    return SettingsStateContainer(
      child: _SettingsBody(emailNotifier: emailNotifier),
    );
  }
}

class _SettingsBody extends StatelessWidget {
  final ValueNotifier<String?> emailNotifier;

  const _SettingsBody({required this.emailNotifier});

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    final hasLoggedIn = Configuration.instance.isLoggedIn();
    final hasConfiguredAccount = Configuration.instance.hasConfiguredAccount();
    final showLoginEntry = isLocalGalleryMode && !hasConfiguredAccount;

    return AnimatedBuilder(
      animation: emailNotifier,
      builder: (context, _) {
        final email = hasLoggedIn ? emailNotifier.value ?? "" : "";
        final title = email.isEmpty
            ? AppLocalizations.of(context).settings
            : email;

        return SettingsPageScaffold(
          title: title,
          actions: _buildHeaderActions(context),
          onTitleDoubleTap: email.isEmpty
              ? null
              : () => _showVerifyIdentityDialog(context),
          onTitleLongPress: email.isEmpty
              ? null
              : () => _showVerifyIdentityDialog(context),
          children: [
            if (showLoginEntry) ...[
              OfflineSettingsBanner(
                onGetStarted: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const EmailEntryPage(
                        showReferralSourceField: false,
                        referralSource: "Offline",
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),
              _buildOfflineLoginCard(context, colors),
              const SizedBox(height: 8),
            ],
            if (hasLoggedIn && !isLocalGalleryMode) ...[
              // Account section
              const StorageCardWidget(),
              const SizedBox(height: 16),
              _buildMenuItem(
                title: AppLocalizations.of(context).account,
                icon: HugeIcons.strokeRoundedUser,
                onTap: () async {
                  await routeToPage(context, const AccountSettingsPage());
                },
              ),
              const SizedBox(height: 8),
              _buildMenuItem(
                title: AppLocalizations.of(context).backup,
                icon: HugeIcons.strokeRoundedCloudUpload,
                onTap: () async {
                  await routeToPage(context, const BackupSettingsPage());
                },
              ),
              const SizedBox(height: 8),
            ],
            // Privacy and personalization section
            _buildMenuItem(
              title: AppLocalizations.of(context).security,
              icon: HugeIcons.strokeRoundedSecurityCheck,
              onTap: () async {
                await routeToPage(context, const SecuritySettingsPage());
              },
            ),
            const SizedBox(height: 8),
            _buildMenuItem(
              title: AppLocalizations.of(context).appearance,
              icon: HugeIcons.strokeRoundedPaintBoard,
              onTap: () async {
                await routeToPage(context, const AppearanceSettingsPage());
              },
            ),
            const SizedBox(height: 8),
            if (isLocalGalleryMode) ...[
              // Local gallery section
              _buildOfflineFeaturesCard(context),
              const SizedBox(height: 8),
            ],
            if (hasLoggedIn && !isLocalGalleryMode) ...[
              // Product features section
              _buildPersonalFeaturesCard(context),
              const SizedBox(height: 8),
              _buildFeaturesAndPlansCard(context),
              const SizedBox(height: 8),
            ],
            // Engagement section
            _buildEngagementCard(context),
            const SizedBox(height: 8),
            // Support section
            _buildMenuItem(
              title: AppLocalizations.of(context).helpAndSupport,
              icon: HugeIcons.strokeRoundedHelpCircle,
              onTap: () async {
                await routeToPage(context, const HelpSupportPage());
              },
            ),
            const SizedBox(height: 8),
            _buildMenuItem(
              title: AppLocalizations.of(context).about,
              icon: HugeIcons.strokeRoundedInformationCircle,
              onTap: () async {
                await routeToPage(context, const AboutUsPage());
              },
            ),
            const SizedBox(height: 8),
            if (hasLoggedIn && !isLocalGalleryMode) ...[
              // Account actions section
              _buildLogoutCard(context),
            ],
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 28),
              child: SocialIconsRow(),
            ),
            const AppVersionWidget(),
            if (hasLoggedIn &&
                !isLocalGalleryMode &&
                (flagService.flags.internalUser || kDebugMode)) ...[
              // Debug section
              _buildMenuItem(
                title: "Debug",
                icon: HugeIcons.strokeRoundedBug02,
                onTap: () async {
                  await routeToPage(context, const DebugSettingsPage());
                },
              ),
              const SizedBox(height: 8),
              _buildMenuItem(
                title: "ML Debug",
                icon: HugeIcons.strokeRoundedAiBrain01,
                onTap: () async {
                  await routeToPage(context, const MLDebugSettingsPage());
                },
              ),
              const SizedBox(height: 16),
            ],
            const SizedBox(height: 60),
          ],
        );
      },
    );
  }

  List<Widget> _buildHeaderActions(BuildContext context) {
    return [
      IconButtonComponent(
        variant: IconButtonComponentVariant.primary,
        shouldSurfaceExecutionStates: false,
        icon: const HugeIcon(icon: HugeIcons.strokeRoundedSearch01),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (context) => const SettingsSearchPage()),
          );
        },
      ),
      if (localSettings.enableDatabaseLogging) ...[
        IconButtonComponent(
          variant: IconButtonComponentVariant.primary,
          shouldSurfaceExecutionStates: false,
          icon: const HugeIcon(icon: HugeIcons.strokeRoundedBug02),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (context) => const LogViewerPage()),
            );
          },
        ),
      ],
    ];
  }

  SettingsItem _buildMenuItem({
    required String title,
    required List<List<dynamic>> icon,
    String? subtitle,
    Widget? trailing,
    Future<void> Function()? onTap,
    bool showOnlyLoadingState = false,
    bool shouldSurfaceExecutionStates = false,
    bool isDestructive = false,
  }) {
    return SettingsItem(
      title: title,
      subtitle: subtitle,
      icon: icon,
      trailing: trailing,
      showOnlyLoadingState: showOnlyLoadingState,
      shouldSurfaceExecutionStates: shouldSurfaceExecutionStates,
      isDestructive: isDestructive,
      onTap: onTap,
    );
  }

  Widget _buildOfflineLoginCard(BuildContext context, ColorTokens colors) {
    return _buildMenuItem(
      title: AppLocalizations.of(context).alreadyHaveAnAccount,
      icon: HugeIcons.strokeRoundedLogin01,
      subtitle: AppLocalizations.of(context).loginToEnte,
      trailing: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: colors.green,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(
          Icons.arrow_forward_rounded,
          color: colors.specialWhite,
          size: 20,
        ),
      ),
      onTap: () async {
        await routeToPage(context, const LoginPage());
      },
    );
  }

  Widget _buildOfflineFeaturesCard(BuildContext context) {
    return MenuGroupComponent(
      items: [
        _buildMenuItem(
          title: AppLocalizations.of(context).machineLearning,
          icon: HugeIcons.strokeRoundedMagicWand01,
          onTap: () async {
            await routeToPage(context, const MachineLearningSettingsPage());
          },
        ),
        _buildMenuItem(
          title: AppLocalizations.of(context).memories,
          icon: HugeIcons.strokeRoundedSparkles,
          onTap: () async {
            await routeToPage(context, const MemoriesSettingsScreen());
          },
        ),
        _buildMenuItem(
          title: AppLocalizations.of(context).notifications,
          icon: HugeIcons.strokeRoundedNotification01,
          onTap: () async {
            await routeToPage(context, const NotificationSettingsScreen());
          },
        ),
        _buildMenuItem(
          title: AppLocalizations.of(context).widgets,
          icon: HugeIcons.strokeRoundedAlignBoxBottomRight,
          onTap: () async {
            await routeToPage(context, const WidgetSettingsScreen());
          },
        ),
        _buildMapsMenuItem(context),
      ],
    );
  }

  Widget _buildPersonalFeaturesCard(BuildContext context) {
    return MenuGroupComponent(
      items: [
        _buildMenuItem(
          title: AppLocalizations.of(context).legacy,
          icon: HugeIcons.strokeRoundedFavourite,
          showOnlyLoadingState: true,
          onTap: () async {
            final hasAuthenticated =
                kDebugMode ||
                await LocalAuthenticationService.instance
                    .requestLocalAuthentication(
                      context,
                      AppLocalizations.of(context).authToManageLegacy,
                    );
            if (hasAuthenticated) {
              if (!context.mounted) return;
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (BuildContext context) {
                    return const EmergencyPage();
                  },
                ),
              );
            }
          },
        ),
        _buildMenuItem(
          title: AppLocalizations.of(context).familyPlans,
          icon: HugeIcons.strokeRoundedUserMultiple,
          showOnlyLoadingState: true,
          shouldSurfaceExecutionStates: true,
          onTap: () async {
            late final UserDetails userDetails;
            try {
              userDetails = await UserService.instance.getUserDetailsV2(
                memoryCount: false,
              );
            } catch (error) {
              if (!context.mounted) {
                return;
              }
              await showGenericErrorDialog(context: context, error: error);
              return;
            }
            if (!context.mounted) {
              return;
            }
            await billingService.launchFamilyPortal(
              context,
              userDetails,
              refreshOnOpen: false,
            );
          },
        ),
        _buildMenuItem(
          title: AppLocalizations.of(context).referrals,
          icon: HugeIcons.strokeRoundedTicketStar,
          onTap: () async {
            await routeToPage(context, const ReferralScreen());
          },
        ),
      ],
    );
  }

  Widget _buildFeaturesAndPlansCard(BuildContext context) {
    return MenuGroupComponent(
      items: [
        _buildMenuItem(
          title: AppLocalizations.of(context).freeUpSpace,
          icon: HugeIcons.strokeRoundedRocket01,
          showOnlyLoadingState: true,
          onTap: () async {
            await routeToPage(context, const FreeUpSpaceOptionsScreen());
          },
        ),
        _buildMenuItem(
          title: AppLocalizations.of(context).machineLearning,
          icon: HugeIcons.strokeRoundedMagicWand01,
          onTap: () async {
            await routeToPage(context, const MachineLearningSettingsPage());
          },
        ),
        _buildMenuItem(
          title: AppLocalizations.of(context).memories,
          icon: HugeIcons.strokeRoundedSparkles,
          onTap: () async {
            await routeToPage(context, const MemoriesSettingsScreen());
          },
        ),
        _buildMenuItem(
          title: AppLocalizations.of(context).notifications,
          icon: HugeIcons.strokeRoundedNotification01,
          onTap: () async {
            await routeToPage(context, const NotificationSettingsScreen());
          },
        ),
        _buildMenuItem(
          title: AppLocalizations.of(context).widgets,
          icon: HugeIcons.strokeRoundedAlignBoxBottomRight,
          onTap: () async {
            await routeToPage(context, const WidgetSettingsScreen());
          },
        ),
        _buildMenuItem(
          title: AppLocalizations.of(context).videoStreaming,
          icon: HugeIcons.strokeRoundedVideoCameraAi,
          onTap: () async {
            await routeToPage(context, const VideoStreamingSettingsPage());
          },
        ),
        if (flagService.enableMultiCast)
          _buildMenuItem(
            title: AppLocalizations.of(context).castSessions,
            icon: HugeIcons.strokeRoundedTvSmart,
            onTap: () async {
              await routeToPage(context, const CastSettingsPage());
            },
          ),
        _buildMapsMenuItem(context),
      ],
    );
  }

  SettingsItem _buildMapsMenuItem(BuildContext context) {
    return _buildMenuItem(
      title: AppLocalizations.of(context).maps,
      icon: HugeIcons.strokeRoundedMaping,
      trailing: ToggleSwitchComponent.async(
        value: () => mapEnabled,
        onChanged: () async {
          final isEnabled = mapEnabled;
          try {
            await setMapEnabled(!isEnabled);
          } catch (e) {
            if (context.mounted) {
              showShortToast(
                context,
                AppLocalizations.of(context).somethingWentWrong,
              );
            }
            rethrow;
          }
        },
      ),
    );
  }

  Widget _buildEngagementCard(BuildContext context) {
    return MenuGroupComponent(
      items: [
        _buildMenuItem(
          title: AppLocalizations.of(context).merchandise,
          icon: HugeIcons.strokeRoundedTShirt,
          onTap: () async {
            await launchUrlString(
              "https://shop.ente.com",
              mode: LaunchMode.externalApplication,
            );
          },
        ),
        _buildMenuItem(
          title: AppLocalizations.of(context).rateUs,
          icon: HugeIcons.strokeRoundedStar,
          onTap: () async {
            final rateUrl = updateService.getRateDetails().item2;
            await launchUrlString(rateUrl);
          },
        ),
      ],
    );
  }

  Widget _buildLogoutCard(BuildContext context) {
    return _buildMenuItem(
      title: AppLocalizations.of(context).logout,
      icon: HugeIcons.strokeRoundedLogout05,
      isDestructive: true,
      onTap: () async {
        _onLogoutTapped(context);
      },
    );
  }

  void _onLogoutTapped(BuildContext context) {
    showChoiceActionSheet(
      context,
      title: AppLocalizations.of(context).warning,
      body: AppLocalizations.of(context).areYouSureYouWantToLogout,
      illustration: Image.asset("assets/warning-grey.png"),
      firstButtonLabel: AppLocalizations.of(context).yes,
      isCritical: true,
      firstButtonOnTap: () async {
        await UserService.instance.logout(context);
      },
    );
  }

  Future<void> _showVerifyIdentityDialog(BuildContext context) async {
    await showDialog(
      useRootNavigator: false,
      context: context,
      builder: (BuildContext context) {
        return VerifyIdentifyDialog(self: true);
      },
    );
  }
}
