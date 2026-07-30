import "dart:io";

import "package:flutter/foundation.dart";
import "package:flutter/material.dart";
import "package:hugeicons/hugeicons.dart";
import "package:photos/core/configuration.dart";
import "package:photos/generated/l10n.dart";
import "package:photos/l10n/l10n.dart";
import "package:photos/service_locator.dart";
import "package:photos/ui/settings/about/about_us_page.dart";
import "package:photos/ui/settings/account/account_settings_page.dart";
import "package:photos/ui/settings/appearance/appearance_settings_page.dart";
import "package:photos/ui/settings/backup/backup_settings_page.dart";
import "package:photos/ui/settings/backup/free_space_options.dart";
import "package:photos/ui/settings/gallery_settings_screen.dart";
import "package:photos/ui/settings/memories_settings_screen.dart";
import "package:photos/ui/settings/ml/machine_learning_settings_page.dart";
import "package:photos/ui/settings/notification_settings_screen.dart";
import "package:photos/ui/settings/search/settings_search_item.dart";
import "package:photos/ui/settings/security/security_settings_page.dart";
import "package:photos/ui/settings/streaming/video_streaming_settings_page.dart";
import "package:photos/ui/settings/support/help_support_page.dart";
import "package:photos/ui/settings/widget_settings_screen.dart";

/// Registry that provides all searchable settings items
class SettingsSearchRegistry {
  static List<SettingsSearchItem> getSearchableItems(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final hasLoggedIn = Configuration.instance.isLoggedIn();
    final isLocalGallery = isLocalGalleryMode;
    final showThemeControls = Platform.isAndroid || kDebugMode;
    final items = <SettingsSearchItem>[];

    // Account settings
    if (hasLoggedIn && !isLocalGallery) {
      items.add(
        SettingsSearchItem(
          title: l10n.account,
          sectionPath: l10n.account,
          icon: HugeIcons.strokeRoundedUser,
          routeBuilder: (_) => const AccountSettingsPage(),
          keywords: ["email", "password", "delete", "subscription"],
        ),
      );

      items.addAll([
        SettingsSearchItem(
          title: l10n.manageSubscription,
          subtitle: l10n.account,
          sectionPath: l10n.account,
          icon: HugeIcons.strokeRoundedCreditCard,
          routeBuilder: (_) => const AccountSettingsPage(),
          isSubPage: true,
          keywords: ["subscription", "plan", "billing", "payment"],
        ),
        SettingsSearchItem(
          title: l10n.changeEmail,
          subtitle: l10n.account,
          sectionPath: l10n.account,
          icon: HugeIcons.strokeRoundedMail01,
          routeBuilder: (_) => const AccountSettingsPage(),
          isSubPage: true,
          keywords: ["email", "mail", "address"],
        ),
        SettingsSearchItem(
          title: l10n.changePassword,
          subtitle: l10n.account,
          sectionPath: l10n.account,
          icon: HugeIcons.strokeRoundedLockPassword,
          routeBuilder: (_) => const AccountSettingsPage(),
          isSubPage: true,
          keywords: ["password", "passphrase", "credentials"],
        ),
        SettingsSearchItem(
          title: l10n.recoveryKey,
          subtitle: l10n.account,
          sectionPath: l10n.account,
          icon: HugeIcons.strokeRoundedKey01,
          routeBuilder: (_) => const AccountSettingsPage(),
          isSubPage: true,
          keywords: ["recovery", "key", "backup key"],
        ),
        SettingsSearchItem(
          title: l10n.exportYourData,
          subtitle: l10n.account,
          sectionPath: l10n.account,
          icon: HugeIcons.strokeRoundedDownload04,
          routeBuilder: (_) => const AccountSettingsPage(),
          isSubPage: true,
          keywords: ["export", "download", "data"],
        ),
        SettingsSearchItem(
          title: l10n.deleteAccount,
          subtitle: l10n.account,
          sectionPath: l10n.account,
          icon: HugeIcons.strokeRoundedDelete02,
          routeBuilder: (_) => const AccountSettingsPage(),
          isSubPage: true,
          keywords: ["delete", "remove", "close account", "close"],
        ),
      ]);
    }

    // Backup settings
    if (hasLoggedIn && !isLocalGallery) {
      items.add(
        SettingsSearchItem(
          title: l10n.backup,
          sectionPath: l10n.backup,
          icon: HugeIcons.strokeRoundedCloudUpload,
          routeBuilder: (_) => const BackupSettingsPage(),
          keywords: ["sync", "upload", "photos", "videos"],
        ),
      );

      items.addAll([
        SettingsSearchItem(
          title: l10n.backedUpFolders,
          subtitle: l10n.backup,
          sectionPath: l10n.backup,
          icon: HugeIcons.strokeRoundedFolder01,
          routeBuilder: (_) => const BackupSettingsPage(),
          isSubPage: true,
          keywords: ["folders", "albums", "camera", "backup folders"],
        ),
        SettingsSearchItem(
          title: l10n.backupStatus,
          subtitle: l10n.backup,
          sectionPath: l10n.backup,
          icon: HugeIcons.strokeRoundedCloudSavingDone01,
          routeBuilder: (_) => const BackupSettingsPage(),
          isSubPage: true,
          keywords: ["status", "progress", "queue", "sync status"],
        ),
        SettingsSearchItem(
          title: l10n.backupSettings,
          subtitle: l10n.backup,
          sectionPath: l10n.backup,
          icon: HugeIcons.strokeRoundedSettings01,
          routeBuilder: (_) => const BackupSettingsPage(),
          isSubPage: true,
          keywords: ["mobile data", "videos", "only new", "resumable"],
        ),
        SettingsSearchItem(
          title: l10n.backupOverMobileData,
          subtitle: l10n.backupSettings,
          sectionPath: "${l10n.backup} > ${l10n.backupSettings}",
          icon: HugeIcons.strokeRoundedSettings01,
          routeBuilder: (_) => const BackupSettingsPage(),
          isSubPage: true,
          keywords: ["mobile data", "cellular", "network"],
        ),
        SettingsSearchItem(
          title: l10n.backupVideos,
          subtitle: l10n.backupSettings,
          sectionPath: "${l10n.backup} > ${l10n.backupSettings}",
          icon: HugeIcons.strokeRoundedVideoCameraAi,
          routeBuilder: (_) => const BackupSettingsPage(),
          isSubPage: true,
          keywords: ["videos", "movies", "backup video"],
        ),
        SettingsSearchItem(
          title: l10n.backupOnlyNewPhotos,
          subtitle: l10n.backupSettings,
          sectionPath: "${l10n.backup} > ${l10n.backupSettings}",
          icon: HugeIcons.strokeRoundedSettings01,
          routeBuilder: (_) => const BackupSettingsPage(),
          isSubPage: true,
          keywords: ["only new", "new photos", "since now"],
        ),
        if (flagService.enableMobMultiPart)
          SettingsSearchItem(
            title: l10n.resumableUploads,
            subtitle: l10n.backupSettings,
            sectionPath: "${l10n.backup} > ${l10n.backupSettings}",
            icon: HugeIcons.strokeRoundedCloudUpload,
            routeBuilder: (_) => const BackupSettingsPage(),
            isSubPage: true,
            keywords: ["resumable", "multipart", "uploads"],
          ),
        if (Platform.isIOS)
          SettingsSearchItem(
            title: l10n.disableAutoLock,
            subtitle: l10n.backupSettings,
            sectionPath: "${l10n.backup} > ${l10n.backupSettings}",
            icon: HugeIcons.strokeRoundedSquareLock02,
            routeBuilder: (_) => const BackupSettingsPage(),
            isSubPage: true,
            keywords: ["auto lock", "screen", "awake"],
          ),
      ]);
    }

    // Security settings
    items.add(
      SettingsSearchItem(
        title: l10n.security,
        sectionPath: l10n.security,
        icon: HugeIcons.strokeRoundedSecurityCheck,
        routeBuilder: (_) => const SecuritySettingsPage(),
        keywords: [
          "lock",
          "pin",
          "biometric",
          "fingerprint",
          "face id",
          "app lock",
          "2fa",
          "two factor",
          "authentication",
          "recovery key",
        ],
      ),
    );

    items.addAll([
      if (Configuration.instance.hasConfiguredAccount() && !isLocalGallery)
        SettingsSearchItem(
          title: l10n.twofactor,
          subtitle: l10n.security,
          sectionPath: l10n.security,
          icon: HugeIcons.strokeRoundedSmartPhone01,
          routeBuilder: (_) => const SecuritySettingsPage(),
          isSubPage: true,
          keywords: ["2fa", "two factor", "authenticator", "otp"],
        ),
      if (Configuration.instance.hasConfiguredAccount() && !isLocalGallery)
        SettingsSearchItem(
          title: l10n.emailVerificationToggle,
          subtitle: l10n.security,
          sectionPath: l10n.security,
          icon: HugeIcons.strokeRoundedMailSecure01,
          routeBuilder: (_) => const SecuritySettingsPage(),
          isSubPage: true,
          keywords: ["email", "verification", "mfa"],
        ),
      if (Configuration.instance.hasConfiguredAccount() && !isLocalGallery)
        SettingsSearchItem(
          title: context.l10n.passkey,
          subtitle: l10n.security,
          sectionPath: l10n.security,
          icon: HugeIcons.strokeRoundedFingerAccess,
          routeBuilder: (_) => const SecuritySettingsPage(),
          isSubPage: true,
          keywords: ["passkey", "webauthn", "biometric"],
        ),
      SettingsSearchItem(
        title: l10n.crashReporting,
        subtitle: l10n.security,
        sectionPath: l10n.security,
        icon: HugeIcons.strokeRoundedBug02,
        routeBuilder: (_) => const SecuritySettingsPage(),
        isSubPage: true,
        keywords: ["crash", "reporting", "diagnostics"],
      ),
      SettingsSearchItem(
        title: l10n.appLock,
        subtitle: l10n.security,
        sectionPath: l10n.security,
        icon: HugeIcons.strokeRoundedSquareLock02,
        routeBuilder: (_) => const SecuritySettingsPage(),
        isSubPage: true,
        keywords: ["lock", "pin", "biometric", "face id", "fingerprint"],
      ),
      if (Configuration.instance.hasConfiguredAccount() && !isLocalGallery)
        SettingsSearchItem(
          title: l10n.activeSessions,
          subtitle: l10n.security,
          sectionPath: l10n.security,
          icon: HugeIcons.strokeRoundedComputerPhoneSync,
          routeBuilder: (_) => const SecuritySettingsPage(),
          isSubPage: true,
          keywords: ["sessions", "devices", "logins"],
        ),
    ]);

    // Appearance settings
    items.add(
      SettingsSearchItem(
        title: l10n.appearance,
        sectionPath: l10n.appearance,
        icon: HugeIcons.strokeRoundedPaintBoard,
        routeBuilder: (_) => const AppearanceSettingsPage(),
        keywords: showThemeControls
            ? ["theme", "dark mode", "light mode", "app icon"]
            : ["app icon"],
      ),
    );

    if (showThemeControls) {
      items.add(
        SettingsSearchItem(
          title: l10n.theme,
          subtitle: l10n.appearance,
          sectionPath: l10n.appearance,
          icon: HugeIcons.strokeRoundedMoon02,
          routeBuilder: (_) => const AppearanceSettingsPage(),
          isSubPage: true,
          keywords: ["theme", "dark mode", "light mode", "system"],
        ),
      );
    }

    items.addAll([
      SettingsSearchItem(
        title: l10n.appIcon,
        subtitle: l10n.appearance,
        sectionPath: l10n.appearance,
        icon: HugeIcons.strokeRoundedImage02,
        routeBuilder: (_) => const AppearanceSettingsPage(),
        isSubPage: true,
        keywords: ["icon", "app icon"],
      ),
      SettingsSearchItem(
        title: l10n.language,
        subtitle: l10n.appearance,
        sectionPath: l10n.appearance,
        icon: HugeIcons.strokeRoundedTranslation,
        routeBuilder: (_) => const AppearanceSettingsPage(),
        isSubPage: true,
        keywords: ["language", "locale", "translation"],
      ),
    ]);

    // Gallery settings (under Appearance)
    items.add(
      SettingsSearchItem(
        title: l10n.gallery,
        subtitle: l10n.appearance,
        sectionPath: "${l10n.appearance} > ${l10n.gallery}",
        icon: HugeIcons.strokeRoundedDashboardSquare02,
        routeBuilder: (_) =>
            const GallerySettingsScreen(fromGalleryLayoutSettingsCTA: false),
        isSubPage: true,
        keywords: ["grid size", "group by", "layout"],
      ),
    );

    // Grid Size setting
    items.add(
      SettingsSearchItem(
        title: l10n.photoGridSize,
        subtitle: l10n.gallery,
        sectionPath: "${l10n.appearance} > ${l10n.gallery}",
        icon: HugeIcons.strokeRoundedDashboardSquare02,
        routeBuilder: (_) =>
            const GallerySettingsScreen(fromGalleryLayoutSettingsCTA: false),
        isSubPage: true,
        keywords: ["grid", "size", "columns", "thumbnail"],
      ),
    );

    // Group By setting
    items.add(
      SettingsSearchItem(
        title: l10n.groupBy,
        subtitle: l10n.gallery,
        sectionPath: "${l10n.appearance} > ${l10n.gallery}",
        icon: HugeIcons.strokeRoundedDashboardSquare02,
        routeBuilder: (_) =>
            const GallerySettingsScreen(fromGalleryLayoutSettingsCTA: false),
        isSubPage: true,
        keywords: ["group", "day", "month", "year"],
      ),
    );

    if (!isLocalGallery) {
      items.add(
        SettingsSearchItem(
          title: l10n.hideSharedItemsFromHomeGallery,
          subtitle: l10n.gallery,
          sectionPath: "${l10n.appearance} > ${l10n.gallery}",
          icon: HugeIcons.strokeRoundedImage01,
          routeBuilder: (_) =>
              const GallerySettingsScreen(fromGalleryLayoutSettingsCTA: false),
          isSubPage: true,
          keywords: ["shared", "hide", "home gallery"],
        ),
      );
    }

    // Machine Learning settings
    if (hasLoggedIn || isLocalGallery) {
      items.add(
        SettingsSearchItem(
          title: l10n.machineLearning,
          sectionPath: l10n.machineLearning,
          icon: HugeIcons.strokeRoundedMagicWand01,
          routeBuilder: (_) => const MachineLearningSettingsPage(),
          keywords: [
            "ml",
            "ai",
            "faces",
            "people",
            "magic search",
            "similar images",
            "duplicates",
          ],
        ),
      );

      items.add(
        SettingsSearchItem(
          title: l10n.localIndexing,
          subtitle: l10n.machineLearning,
          sectionPath: l10n.machineLearning,
          icon: HugeIcons.strokeRoundedDatabase01,
          routeBuilder: (_) => const MachineLearningSettingsPage(),
          isSubPage: true,
          keywords: ["indexing", "local", "on-device"],
        ),
      );
    }

    if (hasLoggedIn || isLocalGallery) {
      items.addAll([
        SettingsSearchItem(
          title: l10n.memories,
          sectionPath: l10n.memories,
          icon: HugeIcons.strokeRoundedSparkles,
          routeBuilder: (_) => const MemoriesSettingsScreen(),
          keywords: ["flashback", "reminder", "highlights"],
        ),
        SettingsSearchItem(
          title: l10n.showMemories,
          subtitle: l10n.memories,
          sectionPath: l10n.memories,
          icon: HugeIcons.strokeRoundedSparkles,
          routeBuilder: (_) => const MemoriesSettingsScreen(),
          isSubPage: true,
          keywords: ["show", "memories", "highlights"],
        ),
        if (memoriesCacheService.curatedMemoriesOption)
          SettingsSearchItem(
            title: l10n.curatedMemories,
            subtitle: l10n.memories,
            sectionPath: l10n.memories,
            icon: HugeIcons.strokeRoundedSparkles,
            routeBuilder: (_) => const MemoriesSettingsScreen(),
            isSubPage: true,
            keywords: ["curated", "smart", "memories"],
          ),
      ]);
    }

    if (hasLoggedIn && !isLocalGallery) {
      items.addAll([
        SettingsSearchItem(
          title: l10n.notifications,
          sectionPath: l10n.notifications,
          icon: HugeIcons.strokeRoundedNotification01,
          routeBuilder: (_) => const NotificationSettingsScreen(),
          keywords: ["alerts", "push", "reminders"],
        ),
        SettingsSearchItem(
          title: l10n.sharedPhotoNotifications,
          subtitle: l10n.notifications,
          sectionPath: l10n.notifications,
          icon: HugeIcons.strokeRoundedNotification01,
          routeBuilder: (_) => const NotificationSettingsScreen(),
          isSubPage: true,
          keywords: ["shared", "notifications", "shares"],
        ),
        SettingsSearchItem(
          title: l10n.socialNotifications,
          subtitle: l10n.notifications,
          sectionPath: l10n.notifications,
          icon: HugeIcons.strokeRoundedNotification01,
          routeBuilder: (_) => const NotificationSettingsScreen(),
          isSubPage: true,
          keywords: [
            "social",
            "comment",
            "comments",
            "like",
            "likes",
            "reply",
            "replies",
            "notifications",
          ],
        ),
        SettingsSearchItem(
          title: l10n.onThisDayMemories,
          subtitle: l10n.notifications,
          sectionPath: l10n.notifications,
          icon: HugeIcons.strokeRoundedNotification01,
          routeBuilder: (_) => const NotificationSettingsScreen(),
          isSubPage: true,
          keywords: ["on this day", "memories", "reminders"],
        ),
        SettingsSearchItem(
          title: l10n.birthdays,
          subtitle: l10n.notifications,
          sectionPath: l10n.notifications,
          icon: HugeIcons.strokeRoundedNotification01,
          routeBuilder: (_) => const NotificationSettingsScreen(),
          isSubPage: true,
          keywords: ["birthday", "birthdays", "reminders"],
        ),
      ]);

      items.addAll([
        SettingsSearchItem(
          title: l10n.widgets,
          sectionPath: l10n.widgets,
          icon: HugeIcons.strokeRoundedAlignBoxBottomRight,
          routeBuilder: (_) => const WidgetSettingsScreen(),
          keywords: ["home screen", "homescreen"],
        ),
        SettingsSearchItem(
          title: l10n.people,
          subtitle: l10n.widgets,
          sectionPath: l10n.widgets,
          icon: HugeIcons.strokeRoundedUserMultiple,
          routeBuilder: (_) => const WidgetSettingsScreen(),
          isSubPage: true,
          keywords: ["people", "faces", "widget"],
        ),
        SettingsSearchItem(
          title: l10n.albums,
          subtitle: l10n.widgets,
          sectionPath: l10n.widgets,
          icon: HugeIcons.strokeRoundedFolder01,
          routeBuilder: (_) => const WidgetSettingsScreen(),
          isSubPage: true,
          keywords: ["albums", "collections", "widget"],
        ),
        SettingsSearchItem(
          title: l10n.memories,
          subtitle: l10n.widgets,
          sectionPath: l10n.widgets,
          icon: HugeIcons.strokeRoundedSparkles,
          routeBuilder: (_) => const WidgetSettingsScreen(),
          isSubPage: true,
          keywords: ["memories", "widget"],
        ),
      ]);

      items.addAll([
        SettingsSearchItem(
          title: l10n.videoStreaming,
          sectionPath: l10n.videoStreaming,
          icon: HugeIcons.strokeRoundedVideoCameraAi,
          routeBuilder: (_) => const VideoStreamingSettingsPage(),
          keywords: ["stream", "playback", "video"],
        ),
        SettingsSearchItem(
          title: l10n.enabled,
          subtitle: l10n.videoStreaming,
          sectionPath: l10n.videoStreaming,
          icon: HugeIcons.strokeRoundedVideoCameraAi,
          routeBuilder: (_) => const VideoStreamingSettingsPage(),
          isSubPage: true,
          keywords: ["enable", "streaming"],
        ),
      ]);
    }

    // Free up space
    if (hasLoggedIn && !isLocalGallery) {
      items.add(
        SettingsSearchItem(
          title: l10n.freeUpSpace,
          sectionPath: l10n.freeUpSpace,
          icon: HugeIcons.strokeRoundedRocket01,
          routeBuilder: (_) => const FreeUpSpaceOptionsScreen(),
          keywords: ["storage", "space", "clean", "delete", "local", "device"],
        ),
      );

      items.addAll([
        SettingsSearchItem(
          title: l10n.freeUpDeviceSpace,
          subtitle: l10n.freeUpSpace,
          sectionPath: l10n.freeUpSpace,
          icon: HugeIcons.strokeRoundedRocket01,
          routeBuilder: (_) => const FreeUpSpaceOptionsScreen(),
          isSubPage: true,
          keywords: ["device space", "storage", "delete"],
        ),
        SettingsSearchItem(
          title: l10n.removeDuplicates,
          subtitle: l10n.freeUpSpace,
          sectionPath: l10n.freeUpSpace,
          icon: HugeIcons.strokeRoundedRocket01,
          routeBuilder: (_) => const FreeUpSpaceOptionsScreen(),
          isSubPage: true,
          keywords: [
            "duplicate",
            "duplicates",
            "same",
            "identical",
            "copy",
            "copies",
          ],
        ),
        if (flagService.enableVectorDb)
          SettingsSearchItem(
            title: l10n.similarImages,
            subtitle: l10n.freeUpSpace,
            sectionPath: l10n.freeUpSpace,
            icon: HugeIcons.strokeRoundedRocket01,
            routeBuilder: (_) => const FreeUpSpaceOptionsScreen(),
            isSubPage: true,
            keywords: ["similar", "alike", "resembling", "cleanup"],
          ),
        SettingsSearchItem(
          title: l10n.viewLargeFiles,
          subtitle: l10n.freeUpSpace,
          sectionPath: l10n.freeUpSpace,
          icon: HugeIcons.strokeRoundedFile01,
          routeBuilder: (_) => const FreeUpSpaceOptionsScreen(),
          isSubPage: true,
          keywords: ["large files", "big", "size", "storage"],
        ),
        SettingsSearchItem(
          title: l10n.deleteSuggestions,
          subtitle: l10n.freeUpSpace,
          sectionPath: l10n.freeUpSpace,
          icon: HugeIcons.strokeRoundedDelete02,
          routeBuilder: (_) => const FreeUpSpaceOptionsScreen(),
          isSubPage: true,
          keywords: ["delete", "suggestions", "cleanup"],
        ),
        SettingsSearchItem(
          title: l10n.manageDeviceStorage,
          subtitle: l10n.freeUpSpace,
          sectionPath: l10n.freeUpSpace,
          icon: HugeIcons.strokeRoundedSettings01,
          routeBuilder: (_) => const FreeUpSpaceOptionsScreen(),
          isSubPage: true,
          keywords: ["storage", "device", "cache"],
        ),
      ]);
    }

    // Help & Support
    items.add(
      SettingsSearchItem(
        title: l10n.helpAndSupport,
        sectionPath: l10n.helpAndSupport,
        icon: HugeIcons.strokeRoundedHelpCircle,
        routeBuilder: (_) => const HelpSupportPage(),
        keywords: ["help", "faq", "contact", "feedback", "bug"],
      ),
    );

    items.addAll([
      SettingsSearchItem(
        title: l10n.browseHelpPages,
        subtitle: l10n.helpAndSupport,
        sectionPath: l10n.helpAndSupport,
        icon: HugeIcons.strokeRoundedHelpCircle,
        routeBuilder: (_) => const HelpSupportPage(),
        isSubPage: true,
        keywords: ["help", "faq", "guide"],
      ),
      SettingsSearchItem(
        title: l10n.reportAnIssue,
        subtitle: l10n.helpAndSupport,
        sectionPath: l10n.helpAndSupport,
        icon: HugeIcons.strokeRoundedBug02,
        routeBuilder: (_) => const HelpSupportPage(),
        isSubPage: true,
        keywords: ["bug", "issue", "crash"],
      ),
      SettingsSearchItem(
        title: l10n.askAQuestion,
        subtitle: l10n.helpAndSupport,
        sectionPath: l10n.helpAndSupport,
        icon: HugeIcons.strokeRoundedHelpCircle,
        routeBuilder: (_) => const HelpSupportPage(),
        isSubPage: true,
        keywords: ["contact", "support", "email"],
      ),
      SettingsSearchItem(
        title: l10n.requestAFeature,
        subtitle: l10n.helpAndSupport,
        sectionPath: l10n.helpAndSupport,
        icon: HugeIcons.strokeRoundedIdea01,
        routeBuilder: (_) => const HelpSupportPage(),
        isSubPage: true,
        keywords: ["suggest", "feature request", "feedback"],
      ),
      SettingsSearchItem(
        title: l10n.exportLogs,
        subtitle: l10n.helpAndSupport,
        sectionPath: l10n.helpAndSupport,
        icon: HugeIcons.strokeRoundedDownload04,
        routeBuilder: (_) => const HelpSupportPage(),
        isSubPage: true,
        keywords: ["logs", "export", "diagnostics"],
      ),
    ]);

    // About
    items.add(
      SettingsSearchItem(
        title: l10n.about,
        sectionPath: l10n.about,
        icon: HugeIcons.strokeRoundedInformationCircle,
        routeBuilder: (_) => const AboutUsPage(),
        keywords: ["version", "privacy", "terms", "license"],
      ),
    );

    items.addAll([
      SettingsSearchItem(
        title: l10n.weAreOpenSource,
        subtitle: l10n.about,
        sectionPath: l10n.about,
        icon: HugeIcons.strokeRoundedGithub,
        routeBuilder: (_) => const AboutUsPage(),
        isSubPage: true,
        keywords: ["open source", "github", "code"],
      ),
      SettingsSearchItem(
        title: l10n.blog,
        subtitle: l10n.about,
        sectionPath: l10n.about,
        icon: HugeIcons.strokeRoundedPencilEdit01,
        routeBuilder: (_) => const AboutUsPage(),
        isSubPage: true,
        keywords: ["blog", "news", "updates"],
      ),
      SettingsSearchItem(
        title: l10n.privacy,
        subtitle: l10n.about,
        sectionPath: l10n.about,
        icon: HugeIcons.strokeRoundedShield01,
        routeBuilder: (_) => const AboutUsPage(),
        isSubPage: true,
        keywords: ["privacy", "policy"],
      ),
      SettingsSearchItem(
        title: l10n.termsOfServicesTitle,
        subtitle: l10n.about,
        sectionPath: l10n.about,
        icon: HugeIcons.strokeRoundedFile01,
        routeBuilder: (_) => const AboutUsPage(),
        isSubPage: true,
        keywords: ["terms", "tos", "service"],
      ),
      if (updateService.isIndependent())
        SettingsSearchItem(
          title: l10n.checkForUpdates,
          subtitle: l10n.about,
          sectionPath: l10n.about,
          icon: HugeIcons.strokeRoundedDownload04,
          routeBuilder: (_) => const AboutUsPage(),
          isSubPage: true,
          keywords: ["updates", "version", "check"],
        ),
    ]);

    return items;
  }

  /// Get suggestions shown when search is empty
  static List<SettingsSearchSuggestion> getSuggestions(
    BuildContext context,
    void Function(Widget Function(BuildContext) routeBuilder) onNavigate,
  ) {
    final l10n = AppLocalizations.of(context);
    final hasLoggedIn = Configuration.instance.isLoggedIn();
    final isLocalGallery = isLocalGalleryMode;

    return [
      // Gallery suggestion
      SettingsSearchSuggestion(
        title: l10n.gallery,
        onTap: () => onNavigate(
          (_) =>
              const GallerySettingsScreen(fromGalleryLayoutSettingsCTA: false),
        ),
      ),
      // App lock suggestion
      SettingsSearchSuggestion(
        title: l10n.appLock,
        onTap: () => onNavigate((_) => const SecuritySettingsPage()),
      ),
      // Free up device space suggestion
      if (hasLoggedIn && !isLocalGallery)
        SettingsSearchSuggestion(
          title: l10n.freeUpDeviceSpace,
          onTap: () => onNavigate((_) => const FreeUpSpaceOptionsScreen()),
        ),
      // Backup settings suggestion
      if (hasLoggedIn && !isLocalGallery)
        SettingsSearchSuggestion(
          title: l10n.backupSettings,
          onTap: () => onNavigate((_) => const BackupSettingsPage()),
        ),
    ];
  }
}
