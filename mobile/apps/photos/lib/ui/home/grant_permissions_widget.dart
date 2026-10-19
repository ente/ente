import "dart:async";
import "dart:io";
import "dart:math";

import "package:ente_components/ente_components.dart";
import 'package:ente_pure_utils/ente_pure_utils.dart';
import "package:ente_strings/ente_strings.dart";
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import "package:hugeicons/hugeicons.dart";
import "package:logging/logging.dart";
import 'package:photo_manager/photo_manager.dart';
import "package:photos/app_mode.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/events/app_mode_changed_event.dart";
import "package:photos/events/permission_granted_event.dart";
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

class _GrantPermissionsWidgetState extends State<GrantPermissionsWidget>
    with WidgetsBindingObserver {
  final Logger _logger = Logger("_GrantPermissionsWidgetState");
  bool _isEnteringLocalGallery = false;
  final Debouncer _onlyNewActionDebouncer = Debouncer(
    const Duration(milliseconds: 500),
    leading: true,
  );
  late final rive.FileLoader _permissionsAnimationLoader;

  static const double _logoWidth = 50;

  @override
  void initState() {
    super.initState();
    _permissionsAnimationLoader = rive.FileLoader.fromAsset(
      "assets/home_tab.riv",
      riveFactory: rive.Factory.flutter,
    );
    WidgetsBinding.instance.addObserver(this);
    unawaited(_enterLocalGalleryIfPermitted());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _permissionsAnimationLoader.dispose();
    _onlyNewActionDebouncer.cancelDebounceTimer();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_enterLocalGalleryIfPermitted());
    }
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
    final skipLabelHeight =
        MediaQuery.textScalerOf(context).scale(TextStyles.body.fontSize!) *
        TextStyles.body.height!;
    return Scaffold(
      backgroundColor: colorScheme.backgroundColour,
      appBar: AppBar(
        backgroundColor: colorScheme.backgroundColour,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        automaticallyImplyLeading: false,
        toolbarHeight: max(kMinInteractiveDimension, skipLabelHeight),
        centerTitle: true,
        title: SvgPicture.asset(
          "packages/ente_components/assets/ente_wordmark.svg",
          width: _logoWidth,
          colorFilter: ColorFilter.mode(colorScheme.content, BlendMode.srcIn),
        ),
        actions: [_buildSkipAction(context)],
      ),
      body: SafeArea(
        top: false,
        child: CustomScrollView(
          slivers: [
            SliverFillRemaining(
              hasScrollBody: false,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 27),
                child: Column(
                  children: [
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(
                          top: Spacing.xl,
                          bottom: Spacing.xxl,
                        ),
                        child: Center(child: _buildHeaderContent(context)),
                      ),
                    ),
                    _buildNewFeatureActionArea(context),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSkipAction(BuildContext context) {
    final color = context.componentColors.primary;
    final toolbarWidth =
        MediaQuery.sizeOf(context).width -
        MediaQuery.paddingOf(context).horizontal;
    return Semantics(
      button: true,
      child: GestureDetector(
        key: const ValueKey("skipForNowButton"),
        behavior: HitTestBehavior.opaque,
        onTap: _onTapSkip,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: kMinInteractiveDimension,
            maxWidth:
                toolbarWidth -
                _logoWidth -
                2 * NavigationToolbar.kMiddleSpacing,
          ),
          child: Padding(
            padding: const EdgeInsets.only(left: 12, right: 18),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    context.strings.skip,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyles.body.copyWith(color: color),
                  ),
                ),
                const SizedBox(width: Spacing.xs),
                ExcludeSemantics(
                  child: HugeIcon(
                    icon: HugeIcons.strokeRoundedArrowRight01,
                    size: IconSizes.small,
                    strokeWidth: 2,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderContent(BuildContext context) {
    final colorScheme = getEnteColorScheme(context);
    final availableWidth =
        MediaQuery.sizeOf(context).width -
        MediaQuery.paddingOf(context).horizontal;

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: max(44.0, (availableWidth - 287) / 2),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 155,
            height: 168,
            child: _buildPermissionsAnimation(),
          ),
          const SizedBox(height: Spacing.xl),
          Text(
            context.strings.readyToBackupTitle,
            textAlign: TextAlign.center,
            style: TextStyles.display2.copyWith(color: colorScheme.content),
          ),
          const SizedBox(height: Spacing.sm),
          Text(
            context.strings.readyToBackupSubtitle,
            textAlign: TextAlign.center,
            style: TextStyles.body.copyWith(color: colorScheme.contentLight),
          ),
        ],
      ),
    );
  }

  Widget _buildPermissionsAnimation() {
    return rive.RiveWidgetBuilder(
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
          showToast(context, context.strings.backingUpLastSevenDaysPhotos);
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
      final wasDecidedBefore =
          Platform.isIOS &&
          await permissionService.getPermissionState() !=
              PermissionState.notDetermined;
      await localSettings.setLocalGalleryOnboardingPending(true);
      final state = await permissionService.requestPhotoMangerPermissions();
      _logger.info("Offline permission state: $state");
      if (state.hasAccess) {
        if (WidgetsBinding.instance.lifecycleState ==
            AppLifecycleState.resumed) {
          await _enterLocalGallery(state);
        }
      } else if (wasDecidedBefore ||
          permissionService.hasAttemptedPermission()) {
        await PhotoManager.openSetting();
      } else {
        await permissionService.setHasAttemptedPermission();
      }
    } catch (e) {
      _logger.severe("Failed to request permission: ${e.toString()}", e);
    }
  }

  Future<void> _enterLocalGalleryIfPermitted() async {
    if (!widget.startWithoutAccount ||
        !localSettings.isLocalGalleryOnboardingPending) {
      return;
    }
    try {
      final state = await permissionService.getPermissionState();
      if (state.hasAccess) {
        await _enterLocalGallery(state);
      }
    } catch (e) {
      _logger.severe("Failed to check permission: ${e.toString()}", e);
    }
  }

  Future<void> _enterLocalGallery(PermissionState state) async {
    if (!mounted || !widget.startWithoutAccount || _isEnteringLocalGallery) {
      return;
    }
    _isEnteringLocalGallery = true;
    try {
      await localSettings.setAppMode(AppMode.localGallery);
      localSettings.localGalleryModeEnabledThisSession = true;
      try {
        await setMLConsent(true);
      } catch (e) {
        _logger.severe("Failed to record ML consent after permission grant", e);
      }
      Bus.instance.fire(AppModeChangedEvent());
      await permissionService.onUpdatePermission(state);
      await localSettings.setLocalGalleryOnboardingPending(false);
    } catch (e) {
      _isEnteringLocalGallery = false;
      rethrow;
    }
    SyncService.instance.onPermissionGranted().ignore();
    Bus.instance.fire(PermissionGrantedEvent());
    try {
      await MLService.instance.init();
      await SemanticSearchService.instance.init();
      unawaited(MLService.instance.runAllML(force: true));
    } catch (e) {
      _logger.severe("Failed to initialize ML after permission grant", e);
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
    await showAlertBottomSheet(
      context,
      title: context.strings.allowPermTitle,
      message: context.strings.allowPermBody,
      assetPath: 'assets/ducky_smart_feature.png',
      buttons: [
        ButtonWidgetV2(
          buttonType: ButtonTypeV2.primary,
          labelText: context.strings.openSettings,
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
      await backupPreferenceService.setSelectAllFoldersForBackup(true);
    }
    SyncService.instance.onPermissionGranted().ignore();
    Bus.instance.fire(PermissionGrantedEvent());
  }

  Widget _buildNewFeatureActionArea(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Spacing.xxl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ButtonComponent(
            key: const ValueKey("selectFoldersButton"),
            density: ButtonComponentDensity.compact,
            label: context.strings.chooseAlbumsToBackup,
            onTap: _onTapSelectFolders,
          ),
          const SizedBox(height: Spacing.md),
          ButtonComponent(
            key: const ValueKey("onlyNewPhotosButton"),
            variant: ButtonComponentVariant.secondary,
            density: ButtonComponentDensity.compact,
            label: context.strings.backupLatestPhotos,
            onTap: () async {
              _onlyNewActionDebouncer.run(() async {
                await _onTapOnlyNewPhotos();
              });
            },
            shouldSurfaceExecutionStates: false,
          ),
        ],
      ),
    );
  }

  Widget _buildOfflinePermissionScreen(BuildContext context) {
    final colorScheme = getEnteColorScheme(context);

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
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(height: 32),
                        ConstrainedBox(
                          constraints: BoxConstraints(
                            maxHeight: MediaQuery.sizeOf(context).height * 0.2,
                          ),
                          child: _buildPermissionsAnimation(),
                        ),
                        const Flexible(child: SizedBox(height: 22)),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 297),
                          child: Text(
                            context.strings.bringMemoriesTogether,
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
                              height: 1.08,
                              color: colorScheme.textBase,
                            ),
                          ),
                        ),
                        const Flexible(child: SizedBox(height: 24)),
                        Text(
                          context.strings.localGalleryPermissionDesc,
                          textAlign: TextAlign.center,
                          style: TextStyles.body.copyWith(
                            color: colorScheme.contentLight.withValues(
                              alpha: 0.8,
                            ),
                          ),
                        ),
                        const Flexible(child: SizedBox(height: 32)),
                        ButtonComponent(
                          variant: ButtonComponentVariant.neutral,
                          density: ButtonComponentDensity.compact,
                          label: context.strings.continueLabel,
                          shouldShowSuccessState: false,
                          onTap: _onTapOfflineGrantPermission,
                        ),
                        const Flexible(child: SizedBox(height: 42)),
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
    final colorScheme = getEnteColorScheme(context);
    final textStyle = TextStyles.body.copyWith(
      color: colorScheme.contentLight.withValues(alpha: 0.8),
    );

    return StyledText(
      text: context.strings.byAgreeing,
      textAlign: TextAlign.center,
      style: textStyle,
      tags: {
        'terms': StyledTextActionTag(
          (String? text, Map<String?, String?> attrs) =>
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (BuildContext context) {
                    return WebPage(
                      context.strings.termsOfServicesTitle,
                      "https://ente.com/terms",
                    );
                  },
                ),
              ),
          style: textStyle.copyWith(
            decoration: TextDecoration.underline,
            decorationColor: textStyle.color,
          ),
        ),
        'policy': StyledTextActionTag(
          (String? text, Map<String?, String?> attrs) =>
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (BuildContext context) {
                    return WebPage(
                      context.strings.privacyPolicyTitle,
                      "https://ente.com/privacy",
                    );
                  },
                ),
              ),
          style: textStyle.copyWith(
            decoration: TextDecoration.underline,
            decorationColor: textStyle.color,
          ),
        ),
      },
    );
  }

  Widget _buildOfflinePermissionHeader(BuildContext context) {
    final colorScheme = getEnteColorScheme(context);
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: SizedBox(
          height: 52,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              HugeIcon(
                icon: HugeIcons.strokeRoundedMenu01,
                size: 18,
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
                size: 18,
                color: colorScheme.strokeBase,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSkeletonGallery(BuildContext context) {
    const skeletonColor = Color.fromRGBO(217, 217, 217, 0.39);
    const memoryAspectRatio = 0.75;
    final topPadding = MediaQuery.of(context).padding.top;

    return Padding(
      padding: EdgeInsets.only(top: topPadding + 56, left: 8, right: 8),
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
                    borderRadius: BorderRadius.circular(13),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          Container(
            width: 71,
            height: 19,
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
