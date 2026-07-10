import "dart:async";
import "dart:math";

import "package:ente_components/ente_components.dart";
import 'package:ente_pure_utils/ente_pure_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import "package:hugeicons/hugeicons.dart";
import "package:logging/logging.dart";
import 'package:photo_manager/photo_manager.dart';
import "package:photos/app_mode.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/events/app_mode_changed_event.dart";
import "package:photos/events/permission_granted_event.dart";
import "package:photos/generated/intl/app_localizations.dart";
import "package:photos/l10n/l10n.dart";
import "package:photos/service_locator.dart";
import "package:photos/services/machine_learning/ml_service.dart";
import "package:photos/services/machine_learning/semantic_search/semantic_search_service.dart";
import 'package:photos/services/sync/sync_service.dart';
import "package:photos/theme/ente_theme.dart";
import "package:photos/ui/common/web_page.dart";
import "package:photos/ui/components/alert_bottom_sheet.dart";
import "package:photos/ui/components/buttons/button_widget_v2.dart";
import "package:photos/ui/notification/toast.dart";
import "package:photos/utils/dialog_util.dart";
import "package:rive/rive.dart" as rive;
import "package:styled_text/styled_text.dart";

class GrantPermissionsWidget extends StatefulWidget {
  const GrantPermissionsWidget({super.key, this.startWithoutAccount = false});

  final bool startWithoutAccount;

  @override
  State<GrantPermissionsWidget> createState() => _GrantPermissionsWidgetState();
}

class _GrantPermissionsWidgetState extends State<GrantPermissionsWidget> {
  final Logger _logger = Logger("_GrantPermissionsWidgetState");
  final Debouncer _onlyNewActionDebouncer = Debouncer(
    const Duration(milliseconds: 500),
    leading: true,
  );
  late final rive.FileLoader _permissionsAnimationLoader;

  @override
  void initState() {
    super.initState();
    _permissionsAnimationLoader = rive.FileLoader.fromAsset(
      "assets/home_tab.riv",
      riveFactory: rive.Factory.flutter,
    );
  }

  @override
  void dispose() {
    _permissionsAnimationLoader.dispose();
    _onlyNewActionDebouncer.cancelDebounceTimer();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.startWithoutAccount) {
      return _buildOfflinePermissionScreen(context);
    }

    return _buildOnlinePermissionScreen(context);
  }

  Widget _buildOnlinePermissionScreen(BuildContext context) {
    final colorScheme = getEnteColorScheme(context);
    return Scaffold(
      backgroundColor: colorScheme.backgroundColour,
      appBar: AppBar(
        backgroundColor: colorScheme.backgroundColour,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        automaticallyImplyLeading: false,
        centerTitle: true,
        title: SvgPicture.asset(
          "assets/ente-branding.svg",
          height: 15,
          colorFilter: ColorFilter.mode(colorScheme.content, BlendMode.srcIn),
        ),
      ),
      body: SafeArea(
        top: false,
        child: CustomScrollView(
          slivers: [
            const SliverPadding(padding: EdgeInsets.only(top: 24)),
            SliverToBoxAdapter(child: _buildHeaderContent(context)),
            SliverFillRemaining(
              hasScrollBody: false,
              child: Padding(
                padding: const EdgeInsets.only(top: 36, bottom: 20),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [_buildNewFeatureActionArea(context)],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderContent(BuildContext context) {
    final colorScheme = getEnteColorScheme(context);

    return Column(
      children: [
        Center(
          child: Padding(
            padding: const EdgeInsets.only(top: 28),
            child: _buildPermissionsAnimation(context),
          ),
        ),
        const SizedBox(height: 22),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            context.l10n.readyToBackupTitle,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: "Nunito",
              fontWeight: FontWeight.w900,
              fontSize: 32,
              letterSpacing: -1.4,
            ).copyWith(color: colorScheme.content),
          ),
        ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            context.l10n.readyToBackupSubtitle,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium!.copyWith(
              fontWeight: FontWeight.w500,
              color: colorScheme.contentLight,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPermissionsAnimation(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.2,
      ),
      child: rive.RiveWidgetBuilder(
        fileLoader: _permissionsAnimationLoader,
        builder: (BuildContext context, rive.RiveState state) {
          if (state is rive.RiveLoaded) {
            return rive.RiveWidget(
              controller: state.controller,
              fit: rive.Fit.contain,
            );
          }
          return const SizedBox.shrink();
        },
      ),
    );
  }

  Future<void> _onTapOnlyNewPhotos() async {
    try {
      final state = await permissionService.requestPhotoMangerPermissions();
      _logger.info("Permission state: $state");
      if (state == PermissionState.authorized ||
          state == PermissionState.limited) {
        await backupPreferenceService.setOnlyNewSinceSevenDaysAgo();
        await onPermissionGranted(state, shouldMarkLimitedFolders: false);
        if (mounted) {
          showToast(context, context.l10n.backingUpLastSevenDaysPhotos);
        }
      } else {
        await _showPermissionDeniedDialog();
      }
    } catch (e) {
      _logger.severe("Failed to request permission: ${e.toString()}", e);
      if (!mounted) return;
      showGenericErrorDialog(context: context, error: e).ignore();
    }
  }

  Future<void> _onTapSelectFolders() async {
    try {
      final state = await permissionService.requestPhotoMangerPermissions();
      _logger.info("Permission state: $state");
      if (state == PermissionState.authorized ||
          state == PermissionState.limited) {
        await onPermissionGranted(state);
      } else {
        await _showPermissionDeniedDialog();
      }
    } catch (e) {
      _logger.severe("Failed to request permission: ${e.toString()}", e);
      if (!mounted) return;
      showGenericErrorDialog(context: context, error: e).ignore();
    }
  }

  Future<void> _onTapOfflineGrantPermission() async {
    try {
      final state = await permissionService.requestPhotoMangerPermissions();
      _logger.info("Offline permission state: $state");
      if (state == PermissionState.authorized ||
          state == PermissionState.limited) {
        await localSettings.setAppMode(AppMode.localGallery);
        localSettings.localGalleryModeEnabledThisSession = true;
        Bus.instance.fire(AppModeChangedEvent());
        await permissionService.onUpdatePermission(state);
        SyncService.instance.onPermissionGranted().ignore();
        Bus.instance.fire(PermissionGrantedEvent());
        try {
          await setMLConsent(true);
          await MLService.instance.init();
          await SemanticSearchService.instance.init();
          unawaited(MLService.instance.runAllML(force: true));
        } catch (e) {
          _logger.severe("Failed to initialize ML after permission grant", e);
        }
      } else {
        await _showPermissionDeniedDialog();
      }
    } catch (e) {
      _logger.severe("Failed to request permission: ${e.toString()}", e);
    }
  }

  Future<void> _onTapSkip() async {
    await backupPreferenceService.setOnboardingPermissionSkipped(true);
    SyncService.instance.sync().ignore();
    if (mounted) {
      setState(() {});
    }
    Bus.instance.fire(PermissionGrantedEvent());
  }

  Future<void> _showPermissionDeniedDialog() async {
    final title = widget.startWithoutAccount
        ? context.l10n.grantPermission
        : context.l10n.allowPermTitle;
    final message = widget.startWithoutAccount
        ? context.l10n.grantPermissionDesc
        : context.l10n.allowPermBody;
    await showAlertBottomSheet(
      context,
      title: title,
      message: message,
      assetPath: 'assets/ducky_smart_feature.png',
      buttons: [
        ButtonWidgetV2(
          buttonType: ButtonTypeV2.primary,
          labelText: context.l10n.openSettings,
          onTap: () async {
            await PhotoManager.openSetting();
          },
        ),
      ],
    );
  }

  Future<void> onPermissionGranted(
    PermissionState state, {
    bool shouldMarkLimitedFolders = true,
  }) async {
    _logger.info("Permission granted " + state.toString());
    await permissionService.onUpdatePermission(state);
    await backupPreferenceService.setOnboardingPermissionSkipped(false);
    if (shouldMarkLimitedFolders && state == PermissionState.limited) {
      // when limited permission is granted, by default mark all folders for
      // backup
      await backupPreferenceService.setSelectAllFoldersForBackup(true);
    }
    SyncService.instance.onPermissionGranted().ignore();
    Bus.instance.fire(PermissionGrantedEvent());
  }

  Widget _buildNewFeatureActionArea(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ButtonWidgetV2(
            key: const ValueKey("selectFoldersButton"),
            buttonType: ButtonTypeV2.primary,
            labelText: context.l10n.selectFoldersForBackup,
            onTap: _onTapSelectFolders,
          ),
          const SizedBox(height: 12),
          ButtonWidgetV2(
            key: const ValueKey("onlyNewPhotosButton"),
            buttonType: ButtonTypeV2.secondary,
            labelText: context.l10n.startWithLatestPhotos,
            onTap: () async {
              _onlyNewActionDebouncer.run(() async {
                await _onTapOnlyNewPhotos();
              });
            },
            shouldSurfaceExecutionStates: false,
          ),
          const SizedBox(height: 12),
          ButtonWidgetV2(
            key: const ValueKey("skipForNowButton"),
            buttonType: ButtonTypeV2.link,
            labelText: context.l10n.doThisLater,
            onTap: _onTapSkip,
            shouldSurfaceExecutionStates: false,
          ),
        ],
      ),
    );
  }

  Widget _buildOfflinePermissionScreen(BuildContext context) {
    final colorScheme = getEnteColorScheme(context);
    final textTheme = getEnteTextTheme(context);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          _buildSkeletonGallery(context),
          _buildOfflinePermissionHeader(context),
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    colorScheme.contentReverse.withValues(alpha: 0.4),
                    colorScheme.contentReverse,
                  ],
                  stops: const [0.0, 0.45],
                ),
              ),
            ),
          ),
          SafeArea(
            child: CustomScrollView(
              primary: false,
              slivers: [
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(height: 32),
                        _buildPermissionsAnimation(context),
                        const Flexible(child: SizedBox(height: 22)),
                        Text(
                          AppLocalizations.of(
                            context,
                          ).grantGalleryPermissionTitle,
                          textAlign: .center,
                          textScaler: .noScaling,
                          style: TextStyle(
                            fontWeight: .w900,
                            fontFamily: TextStyles.outfitFontFamily,
                            package: TextStyles.fontPackage,
                            fontSize: min(
                              MediaQuery.of(context).size.width * 0.125,
                              32,
                            ),
                            height: 1,
                            color: colorScheme.textBase,
                          ),
                        ),
                        const Flexible(child: SizedBox(height: 24)),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Text(
                            AppLocalizations.of(
                              context,
                            ).grantGalleryPermissionDesc,
                            textAlign: TextAlign.center,
                            style: textTheme.body.copyWith(
                              color: colorScheme.textMuted,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        const Flexible(child: SizedBox(height: 32)),
                        ButtonWidgetV2(
                          buttonType: ButtonTypeV2.neutral,
                          labelText: AppLocalizations.of(
                            context,
                          ).grantPermission,
                          onTap: _onTapOfflineGrantPermission,
                        ),
                        const Flexible(child: SizedBox(height: 20)),
                        _buildOfflineTermsAndPrivacy(context),
                        const Flexible(child: SizedBox(height: 24)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOfflineTermsAndPrivacy(BuildContext context) {
    final textTheme = getEnteTextTheme(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: StyledText(
        text: AppLocalizations.of(context).byAgreeing,
        textAlign: TextAlign.center,
        style: textTheme.bodyMuted,
        tags: {
          'terms': StyledTextActionTag(
            (String? text, Map<String?, String?> attrs) =>
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (BuildContext context) {
                      return WebPage(
                        AppLocalizations.of(context).termsOfServicesTitle,
                        "https://ente.com/terms",
                      );
                    },
                  ),
                ),
            style: textTheme.bodyMuted.copyWith(
              decoration: TextDecoration.underline,
              decorationColor: textTheme.bodyMuted.color,
            ),
          ),
          'policy': StyledTextActionTag(
            (String? text, Map<String?, String?> attrs) =>
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (BuildContext context) {
                      return WebPage(
                        AppLocalizations.of(context).privacyPolicyTitle,
                        "https://ente.com/privacy",
                      );
                    },
                  ),
                ),
            style: textTheme.bodyMuted.copyWith(
              decoration: TextDecoration.underline,
              decorationColor: textTheme.bodyMuted.color,
            ),
          ),
        },
      ),
    );
  }

  Widget _buildOfflinePermissionHeader(BuildContext context) {
    final colorScheme = getEnteColorScheme(context);
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: SizedBox(
          height: 52,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              HugeIcon(
                icon: HugeIcons.strokeRoundedMenu01,
                size: 24,
                color: colorScheme.strokeBase,
              ),
              SvgPicture.asset(
                "assets/ente-branding.svg",
                height: 15,
                colorFilter: ColorFilter.mode(
                  colorScheme.content,
                  BlendMode.srcIn,
                ),
              ),
              HugeIcon(
                icon: HugeIcons.strokeRoundedUpload01,
                size: 24,
                color: colorScheme.strokeBase,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSkeletonGallery(BuildContext context) {
    const skeletonColor = Color.fromRGBO(217, 217, 217, 0.4);
    const memoryAspectRatio = 0.75;
    final topPadding = MediaQuery.of(context).padding.top;

    return Padding(
      padding: EdgeInsets.only(top: topPadding + 56, left: 16, right: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 3 * memoryAspectRatio,
            child: GridView.builder(
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 4,
                childAspectRatio: memoryAspectRatio,
              ),
              itemCount: 3,
              itemBuilder: (context, index) {
                return Container(
                  decoration: BoxDecoration(
                    color: skeletonColor,
                    borderRadius: BorderRadius.circular(14),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          Container(
            width: 72,
            height: 20,
            decoration: BoxDecoration(
              color: skeletonColor,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: GridView.builder(
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 4,
                mainAxisSpacing: 4,
              ),
              itemCount: 9,
              itemBuilder: (context, index) {
                return Container(
                  decoration: BoxDecoration(
                    color: skeletonColor,
                    borderRadius: BorderRadius.circular(8),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
