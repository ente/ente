import "dart:async";

import "package:ente_components/ente_components.dart";
import "package:flutter/material.dart";
import "package:hugeicons/hugeicons.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/events/notification_event.dart";
import "package:photos/generated/l10n.dart";
import "package:photos/service_locator.dart";
import "package:photos/services/machine_learning/ml_indexing_isolate.dart";
import "package:photos/services/machine_learning/ml_model_assets.dart";
import "package:photos/services/machine_learning/ml_model_download_service.dart";
import "package:photos/services/machine_learning/ml_service.dart";
import "package:photos/services/machine_learning/semantic_search/semantic_search_service.dart";
import "package:photos/services/remote_assets_service.dart";
import "package:photos/services/wake_lock_service.dart";
import "package:photos/ui/common/loading_widget.dart";
import "package:photos/ui/common/web_page.dart";
import "package:photos/ui/settings/components/settings_page_scaffold.dart";
import "package:photos/ui/settings/ml/ml_user_dev_screen.dart";
import "package:photos/utils/ml_util.dart";
import "package:photos/utils/network_util.dart";

class MachineLearningSettingsPage extends StatefulWidget {
  const MachineLearningSettingsPage({super.key});

  @override
  State<MachineLearningSettingsPage> createState() =>
      _MachineLearningSettingsPageState();
}

class _MachineLearningSettingsPageState
    extends State<MachineLearningSettingsPage> {
  Timer? _timer;
  int _titleTapCount = 0;
  Timer? _advancedOptionsTimer;
  bool _hasAcknowledgedMLConsent = false;
  bool _hasHandledDisabledExit = false;

  @override
  void initState() {
    super.initState();
    wakeLockService.updateWakeLock(
      enable: true,
      wakeLockFor: WakeLockFor.machineLearningSettingsScreen,
    );
    computeController.forceOverrideML(turnOn: true);
    if (!MLModelDownloadService.instance.areModelsDownloaded(
      onlyIndexingModels: false,
    )) {
      _timer = Timer.periodic(const Duration(seconds: 10), (timer) {
        if (mounted) {
          setState(() {});
        }
      });
    }
    _advancedOptionsTimer = Timer.periodic(const Duration(seconds: 7), (timer) {
      _titleTapCount = 0;
    });
  }

  @override
  void dispose() {
    super.dispose();
    wakeLockService.updateWakeLock(
      enable: false,
      wakeLockFor: WakeLockFor.machineLearningSettingsScreen,
    );
    computeController.forceOverrideML(turnOn: false);
    _timer?.cancel();
    _advancedOptionsTimer?.cancel();
  }

  @override
  Widget build(BuildContext context) {
    final hasEnabled = hasGrantedMLConsent;

    if (!hasEnabled) {
      return _buildDisabledMLScreen(context);
    }

    return _buildEnabledMLScreen(context);
  }

  Widget _buildEnabledMLScreen(BuildContext context) {
    final colors = context.componentColors;

    return SettingsPageScaffold(
      title: AppLocalizations.of(context).machineLearning,
      onTitleTap: _handleEnabledTitleTap,
      children: [
        Text(
          AppLocalizations.of(context).mlIndexingDescription,
          textAlign: TextAlign.left,
          style: TextStyles.mini.copyWith(color: colors.textLight),
        ),
        const SizedBox(height: 20),
        _getMlSettings(context),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildDisabledMLScreen(BuildContext context) {
    return SettingsPageScaffold(
      title: AppLocalizations.of(context).mlConsent,
      children: [
        _buildDisabledMLDescription(context),
        const SizedBox(height: 20),
        Center(
          child: Image.asset(
            "assets/ducky_ml.png",
            height: 150,
            fit: BoxFit.contain,
          ),
        ),
        const SizedBox(height: 18),
        _buildDisabledConsentAckRow(context),
        const SizedBox(height: 20),
        ButtonComponent(
          label: AppLocalizations.of(context).mlConsent,
          isDisabled: !_hasAcknowledgedMLConsent,
          onTap: () async {
            if (!_hasAcknowledgedMLConsent) return;
            await toggleMlConsent();
          },
        ),
        const SizedBox(height: 12),
        ButtonComponent(
          label: AppLocalizations.of(context).cancel,
          variant: ButtonComponentVariant.secondary,
          onTap: () async {
            await _handleDisabledScreenExit();
            if (context.mounted) {
              Navigator.of(context).pop();
            }
          },
        ),
      ],
    );
  }

  void _handleEnabledTitleTap() {
    var shouldOpenDeveloperOptions = false;
    setState(() {
      _titleTapCount++;
      if (_titleTapCount >= 7) {
        _titleTapCount = 0;
        shouldOpenDeveloperOptions = true;
      }
    });

    if (!shouldOpenDeveloperOptions) {
      return;
    }
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (BuildContext context) {
              return const MLUserDeveloperOptions(mlIsEnabled: true);
            },
          ),
        )
        .ignore();
  }

  Future<void> _handleDisabledScreenExit() async {
    if (_hasHandledDisabledExit || hasGrantedMLConsent) {
      return;
    }
    _hasHandledDisabledExit = true;
    await localSettings.setHasSeenMLEnablingBanner();
    Bus.instance.fire(NotificationEvent());
  }

  Future<void> toggleMlConsent() async {
    final oldMlConsent = hasGrantedMLConsent;
    final oldMlEnabled = oldMlConsent && localSettings.isMLLocalIndexingEnabled;
    final mlConsent = !oldMlConsent;
    await setMLConsent(mlConsent);
    final newMlEnabled = mlConsent && localSettings.isMLLocalIndexingEnabled;
    // Queue a memories cache refresh so People/Clip memories appear or
    // disappear on the next scheduled recompute. We intentionally only queue
    // here — the actual recompute will be picked up by the next updateCache
    // invocation (runAllML after indexing, or the startup self-schedule).
    memoriesCacheService.queueUpdateCache();
    Bus.instance.fire(NotificationEvent());
    if (!mlConsent) {
      MLService.instance.pauseIndexingAndClustering();
      unawaited(MLIndexingIsolate.instance.cleanupLocalIndexingModels());
      if (oldMlEnabled && !newMlEnabled) {
        await memoriesCacheService.purgeMlOnlyMemoriesFromCache();
      }
    } else {
      await MLService.instance.init();
      await SemanticSearchService.instance.init();
      unawaited(MLService.instance.runAllML(force: true));
    }
    if (mounted) {
      setState(() {});
    }
  }

  Widget _buildDisabledMLDescription(BuildContext context) {
    final colors = context.componentColors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          AppLocalizations.of(context).mlConsentDescription,
          textAlign: TextAlign.left,
          style: TextStyles.mini.copyWith(color: colors.textLight),
        ),
        const SizedBox(height: 6),
        GestureDetector(
          onTap: () async => _openMLPrivacyPolicy(context),
          child: Text(
            AppLocalizations.of(context).mlConsentPrivacy,
            textAlign: TextAlign.left,
            style: TextStyles.mini.copyWith(
              color: colors.textLight,
              decoration: TextDecoration.underline,
              decorationColor: colors.textLight,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDisabledConsentAckRow(BuildContext context) {
    final colors = context.componentColors;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        setState(() {
          _hasAcknowledgedMLConsent = !_hasAcknowledgedMLConsent;
        });
      },
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CheckboxComponent(
            selected: _hasAcknowledgedMLConsent,
            onChanged: (_) {
              setState(() {
                _hasAcknowledgedMLConsent = !_hasAcknowledgedMLConsent;
              });
            },
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              AppLocalizations.of(context).mlConsentConfirmation,
              style: TextStyles.mini.copyWith(color: colors.textLight),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openMLPrivacyPolicy(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (BuildContext context) {
          return WebPage(
            AppLocalizations.of(context).privacyPolicyTitle,
            "https://ente.com/privacy",
          );
        },
      ),
    );
  }

  Widget _getMlSettings(BuildContext context) {
    final hasEnabled = hasGrantedMLConsent;
    if (!hasEnabled) {
      return const SizedBox.shrink();
    }
    return Column(
      children: [
        MenuComponent(
          title: AppLocalizations.of(context).enabled,
          leading: const HugeIcon(
            icon: HugeIcons.strokeRoundedToggleOn,
            size: IconSizes.small,
          ),
          trailing: ToggleSwitchComponent.async(
            value: () => hasEnabled,
            onChanged: () async {
              await toggleMlConsent();
            },
          ),
        ),
        const SizedBox(height: 8),
        MenuComponent(
          title: AppLocalizations.of(context).localIndexing,
          leading: const HugeIcon(
            icon: HugeIcons.strokeRoundedCpu,
            size: IconSizes.small,
          ),
          trailing: ToggleSwitchComponent.async(
            value: () => localSettings.isMLLocalIndexingEnabled,
            onChanged: () async {
              final oldMlEnabled =
                  hasGrantedMLConsent && localSettings.isMLLocalIndexingEnabled;
              final localIndexing = await localSettings.toggleLocalMLIndexing();
              final newMlEnabled = hasGrantedMLConsent && localIndexing;
              memoriesCacheService.queueUpdateCache();
              Bus.instance.fire(NotificationEvent());
              if (localIndexing) {
                unawaited(MLService.instance.runAllML(force: true));
              } else {
                MLService.instance.pauseIndexingAndClustering();
                unawaited(
                  MLIndexingIsolate.instance.cleanupLocalIndexingModels(),
                );
                if (oldMlEnabled && !newMlEnabled) {
                  await memoriesCacheService.purgeMlOnlyMemoriesFromCache();
                }
              }

              if (mounted) {
                setState(() {});
              }
            },
          ),
        ),
        const SizedBox(height: 12),
        MLModelDownloadService.instance.areModelsDownloaded(
                  onlyIndexingModels: true,
                ) ||
                !localSettings.isMLLocalIndexingEnabled
            ? const MLStatusWidget()
            : const ModelLoadingState(),
      ],
    );
  }
}

class ModelLoadingState extends StatefulWidget {
  const ModelLoadingState({super.key});

  @override
  State<ModelLoadingState> createState() => _ModelLoadingStateState();
}

class _ModelLoadingStateState extends State<ModelLoadingState> {
  StreamSubscription<(String, int, int)>? _progressStream;
  final Map<String, (int, int)> _progressMap = {};
  Timer? _timer;

  @override
  void initState() {
    _progressStream = RemoteAssetsService.instance.progressStream.listen((
      event,
    ) {
      final String url = event.$1;
      String title = "";
      if (url.contains(ClipImageModel.remoteFileName)) {
        title = "Image Model";
      } else if (url.contains(ClipTextModel.remoteFileName)) {
        title = "Text Model";
      } else if (url.contains(FaceDetectionModel.remoteFileName)) {
        title = "Face Detection Model";
      } else if (url.contains(FaceEmbeddingModel.remoteFileName)) {
        title = "Face Embedding Model";
      }
      if (title.isNotEmpty) {
        _progressMap[title] = (event.$2, event.$3);
        setState(() {});
      }
    });
    _timer = Timer.periodic(const Duration(seconds: 10), (timer) {
      setState(() {});
    });
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
    _progressStream?.cancel();
    _timer?.cancel();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.only(left: Spacing.sm, top: 6, bottom: 6),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              AppLocalizations.of(context).status.toUpperCase(),
              style: TextStyles.mini.copyWith(color: colors.textLight),
            ),
          ),
        ),
        const SizedBox(height: 8),
        FutureBuilder(
          future: canUseHighBandwidth().then((v) => isLocalGalleryMode || v),
          builder: (context, snapshot) {
            String title = "";
            List<List<dynamic>> leadingIcon = HugeIcons.strokeRoundedLoading03;
            if (snapshot.hasData) {
              if (snapshot.data!) {
                MLModelDownloadService.instance.triggerModelsDownload(
                  onlyIndexingModels: false,
                );
                title = AppLocalizations.of(context).checkingModels;
                leadingIcon = HugeIcons.strokeRoundedCloudDownload;
              } else {
                title = AppLocalizations.of(context).waitingForWifi;
                leadingIcon = HugeIcons.strokeRoundedWifi02;
              }
            }
            return MenuComponent(
              title: title,
              leading: HugeIcon(icon: leadingIcon, size: IconSizes.small),
              trailing: EnteLoadingWidget(size: 12, color: colors.fillDark),
            );
          },
        ),
        // show the progress map if in debug mode
        ..._progressMap.entries.map((entry) {
          return Padding(
            padding: const EdgeInsets.only(top: 8),
            child: MenuComponent(
              key: ValueKey(entry.value),
              title: entry.key,
              leading: const HugeIcon(
                icon: HugeIcons.strokeRoundedCloudDownload,
                size: IconSizes.small,
              ),
              trailing: Text(
                '${(entry.value.$1 * 100) ~/ entry.value.$2}%',
                style: TextStyles.mini.copyWith(color: colors.textLight),
              ),
            ),
          );
        }),
      ],
    );
  }
}

class MLStatusWidget extends StatefulWidget {
  const MLStatusWidget({super.key});

  @override
  State<MLStatusWidget> createState() => MLStatusWidgetState();
}

class MLStatusWidgetState extends State<MLStatusWidget> {
  Timer? _timer;
  bool _isDeviceHealthy = computeController.isDeviceHealthy;
  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 10), (timer) {
      MLService.instance.triggerML();
      _isDeviceHealthy = computeController.isDeviceHealthy;
      setState(() {});
    });
  }

  Future<IndexStatus> _getIndexStatus() async {
    final status = await getIndexStatus();
    return status;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.only(left: Spacing.sm, top: 6, bottom: 6),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              AppLocalizations.of(context).status.toUpperCase(),
              style: TextStyles.mini.copyWith(color: colors.textLight),
            ),
          ),
        ),
        const SizedBox(height: 8),
        FutureBuilder(
          future: _getIndexStatus(),
          builder: (context, snapshot) {
            if (snapshot.hasData) {
              final int indexedFiles = snapshot.data!.indexedItems;
              final int pendingFiles = snapshot.data!.pendingItems;
              final int total = indexedFiles + pendingFiles;
              final bool hasWifi = snapshot.data!.hasWifiEnabled!;

              if (!_isDeviceHealthy && pendingFiles > 0) {
                return Text(
                  AppLocalizations.of(context).indexingPausedStatusDescription,
                  style: TextStyles.mini.copyWith(color: colors.textLight),
                );
              }

              return Column(
                children: [
                  MenuComponent(
                    key: ValueKey("pending_items_$pendingFiles"),
                    title: AppLocalizations.of(context).processed,
                    leading: const HugeIcon(
                      icon: HugeIcons.strokeRoundedClock01,
                      size: IconSizes.small,
                    ),
                    trailing: Text(
                      total < 1
                          ? 'NA'
                          : pendingFiles == 0
                          ? '100%'
                          : '${(indexedFiles * 100.0 / total * 1.0).toStringAsFixed(2)}%',
                      style: TextStyles.mini.copyWith(color: colors.textLight),
                    ),
                  ),
                  if (MLService.instance.showClusteringIsHappening)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: MenuComponent(
                        title: AppLocalizations.of(context).clusteringProgress,
                        leading: const HugeIcon(
                          icon: HugeIcons.strokeRoundedSparkles,
                          size: IconSizes.small,
                        ),
                        trailing: Text(
                          AppLocalizations.of(context).currentlyRunning,
                          style: TextStyles.mini.copyWith(
                            color: colors.textLight,
                          ),
                        ),
                      ),
                    )
                  else if (!hasWifi && pendingFiles > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: MenuComponent(
                        title: AppLocalizations.of(context).waitingForWifi,
                        leading: const HugeIcon(
                          icon: HugeIcons.strokeRoundedWifi02,
                          size: IconSizes.small,
                        ),
                      ),
                    ),
                ],
              );
            }
            return const EnteLoadingWidget();
          },
        ),
      ],
    );
  }
}
