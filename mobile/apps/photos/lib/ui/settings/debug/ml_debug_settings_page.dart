import "dart:async";

import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:flutter/material.dart";
import "package:hugeicons/hugeicons.dart";
import "package:logging/logging.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/db/ml/db.dart";
import "package:photos/db/ml/rust_db.dart";
import "package:photos/events/people_changed_event.dart";
import "package:photos/models/ml/face/person.dart";
import "package:photos/service_locator.dart";
import "package:photos/services/machine_learning/face_ml/face_clustering/face_clustering_service.dart";
import "package:photos/services/machine_learning/face_ml/person/person_service.dart";
import "package:photos/services/machine_learning/ml_indexing_isolate.dart";
import "package:photos/services/machine_learning/ml_model_download_service.dart";
import "package:photos/services/machine_learning/ml_process_lock.dart";
import "package:photos/services/machine_learning/ml_run_control.dart";
import "package:photos/services/machine_learning/ml_service.dart";
import "package:photos/services/machine_learning/semantic_search/semantic_search_service.dart";
import "package:photos/services/rewind/rewind_edition.dart";
import "package:photos/services/rewind/rewind_snapshot.dart";
import "package:photos/src/rust/api/ml_db_api.dart" as rust;
import "package:photos/theme/ente_theme.dart";
import "package:photos/ui/components/menu_item_widget/menu_item_widget_new.dart";
import "package:photos/ui/components/settings/settings_grouped_card.dart";
import "package:photos/ui/components/toggle_switch_widget.dart";
import "package:photos/ui/notification/toast.dart";
import "package:photos/ui/rewind/debug/rewind_gallery_page.dart";
import "package:photos/ui/settings/debug/memories_debug_page.dart";
import "package:photos/utils/dialog_util.dart";
import "package:photos/utils/ml_util.dart";

typedef _VectorIndexStatus = ({rust.FillState state, int vectors});

class MLDebugSettingsPage extends StatefulWidget {
  const MLDebugSettingsPage({super.key});

  @override
  State<MLDebugSettingsPage> createState() => _MLDebugSettingsPageState();
}

class _MLDebugSettingsPageState extends State<MLDebugSettingsPage> {
  final Logger logger = Logger("MLDebugSettingsPage");
  late final mlDataDB = MLDataDB.instance;
  static const double _autoMergeMin = 0.01;
  static const double _autoMergeMax = 0.35;
  static const double _clusteringMin = 0.10;
  static const double _clusteringMax = 0.35;
  static const double _thresholdStep = 0.01;

  late double _autoMergeThreshold;
  late double _defaultClusteringDistance;
  late bool _persistAutoMergeThreshold;
  late bool _persistDefaultClusteringDistance;

  @override
  void initState() {
    super.initState();
    final savedAutoMerge = localSettings.autoMergeThresholdOverride;
    _persistAutoMergeThreshold = true;
    _autoMergeThreshold = _clampThreshold(
      savedAutoMerge ?? PersonService.autoMergeThreshold,
      _autoMergeMin,
      _autoMergeMax,
    );
    PersonService.autoMergeThreshold = _autoMergeThreshold;
    if (savedAutoMerge != null) {
      unawaited(
        localSettings.setAutoMergeThresholdOverride(_autoMergeThreshold),
      );
    }
    final savedClustering = localSettings.defaultClusteringDistanceOverride;
    _persistDefaultClusteringDistance = true;
    _defaultClusteringDistance = _clampThreshold(
      savedClustering ?? FaceClusteringService.defaultDistanceThreshold,
      _clusteringMin,
      _clusteringMax,
    );
    FaceClusteringService.defaultDistanceThreshold = _defaultClusteringDistance;
    if (savedClustering != null) {
      unawaited(
        localSettings.setDefaultClusteringDistanceOverride(
          _defaultClusteringDistance,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = getEnteColorScheme(context);
    final textTheme = getEnteTextTheme(context);

    return Scaffold(
      backgroundColor: colorScheme.backgroundColour,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 24),
              GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: Icon(
                  Icons.arrow_back,
                  color: colorScheme.strokeBase,
                  size: 24,
                ),
              ),
              const SizedBox(height: 24),
              Text("ML Debug", style: textTheme.h3Bold),
              const SizedBox(height: 24),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      _buildMLControlsCard(context),
                      const SizedBox(height: 8),
                      if (MLDataDB.isRustBackend) ...[
                        _buildVectorIndexCard(context),
                        const SizedBox(height: 8),
                      ],
                      _buildThresholdsCard(context),
                      const SizedBox(height: 8),
                      _buildMLActionsCard(context),
                      const SizedBox(height: 8),
                      _buildResetActionsCard(context),
                      const SizedBox(height: 60),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMLControlsCard(BuildContext context) {
    return SettingsGroupedCard(
      children: [
        MenuItemWidgetNew(
          title: "ML Consent",
          leadingIconWidget: _buildIconWidget(
            context,
            HugeIcons.strokeRoundedAiBrain01,
          ),
          trailingWidget: ToggleSwitchWidget(
            value: () => hasGrantedMLConsent,
            onChanged: _onMLConsentChanged,
          ),
        ),
        MenuItemWidgetNew(
          title: "Remote fetch",
          leadingIconWidget: _buildIconWidget(
            context,
            HugeIcons.strokeRoundedCloud,
          ),
          trailingWidget: ToggleSwitchWidget(
            value: () => localSettings.remoteFetchEnabled,
            onChanged: _onRemoteFetchChanged,
          ),
        ),
        MenuItemWidgetNew(
          title: "Local indexing",
          leadingIconWidget: _buildIconWidget(
            context,
            HugeIcons.strokeRoundedSmartPhone01,
          ),
          trailingWidget: ToggleSwitchWidget(
            value: () => localSettings.isMLLocalIndexingEnabled,
            onChanged: _onLocalIndexingChanged,
          ),
        ),
        MenuItemWidgetNew(
          title: "Auto indexing",
          leadingIconWidget: _buildIconWidget(
            context,
            HugeIcons.strokeRoundedRefresh,
          ),
          trailingWidget: ToggleSwitchWidget(
            value: () => !MLService.instance.debugIndexingDisabled,
            onChanged: _onAutoIndexingChanged,
          ),
        ),
        MenuItemWidgetNew(
          title: "Run ML on interactions",
          leadingIconWidget: _buildIconWidget(
            context,
            HugeIcons.strokeRoundedPlay,
          ),
          trailingWidget: ToggleSwitchWidget(
            value: () => localSettings.runMLDuringInteractionOverride,
            onChanged: _onRunMLDuringInteractionChanged,
          ),
        ),
        MenuItemWidgetNew(
          title: "Pet recognition",
          leadingIconWidget: _buildIconWidget(
            context,
            HugeIcons.strokeRoundedAiImage,
          ),
          trailingWidget: ToggleSwitchWidget(
            value: () => localSettings.petRecognitionEnabled,
            onChanged: _onPetRecognitionChanged,
          ),
        ),
      ],
    );
  }

  Widget _buildMLActionsCard(BuildContext context) {
    return SettingsGroupedCard(
      children: [
        MenuItemWidgetNew(
          title: "Trigger run ML",
          leadingIconWidget: _buildIconWidget(
            context,
            HugeIcons.strokeRoundedPlay,
          ),
          trailingIcon: Icons.chevron_right_outlined,
          trailingIconIsMuted: true,
          onTap: () async => _onTriggerRunML(context),
        ),
        MenuItemWidgetNew(
          title: "Trigger run indexing",
          leadingIconWidget: _buildIconWidget(
            context,
            HugeIcons.strokeRoundedSearch01,
          ),
          trailingIcon: Icons.chevron_right_outlined,
          trailingIconIsMuted: true,
          onTap: () async => _onTriggerRunIndexing(context),
        ),
        MenuItemWidgetNew(
          title: "Trigger clustering",
          leadingIconWidget: _buildIconWidget(
            context,
            HugeIcons.strokeRoundedUserMultiple,
          ),
          trailingIcon: Icons.chevron_right_outlined,
          trailingIconIsMuted: true,
          onTap: () async => _onTriggerClustering(context),
        ),
        MenuItemWidgetNew(
          title: "ML process lock state",
          leadingIconWidget: _buildIconWidget(
            context,
            HugeIcons.strokeRoundedLock,
          ),
          trailingIcon: Icons.chevron_right_outlined,
          trailingIconIsMuted: true,
          onTap: () async => _onShowProcessLockState(context),
        ),
        MenuItemWidgetNew(
          title: "Update discover",
          leadingIconWidget: _buildIconWidget(
            context,
            HugeIcons.strokeRoundedCompass01,
          ),
          trailingIcon: Icons.chevron_right_outlined,
          trailingIconIsMuted: true,
          onTap: () async => _onUpdateDiscover(context),
        ),
        MenuItemWidgetNew(
          title: "Update memories",
          leadingIconWidget: _buildIconWidget(
            context,
            HugeIcons.strokeRoundedSparkles,
          ),
          trailingIcon: Icons.chevron_right_outlined,
          trailingIconIsMuted: true,
          onTap: () async => _onUpdateMemories(context),
        ),
        MenuItemWidgetNew(
          title: "Show all memories debug",
          leadingIconWidget: Icon(
            Icons.bug_report_outlined,
            color: getEnteColorScheme(context).menuItemIconStroke,
            size: 20,
          ),
          trailingIcon: Icons.chevron_right_outlined,
          trailingIconIsMuted: true,
          onTap: () async => _onShowAllMemoriesDebug(context),
        ),
        MenuItemWidgetNew(
          title: "Show all legacy trip memories",
          leadingIconWidget: Icon(
            Icons.map_outlined,
            color: getEnteColorScheme(context).menuItemIconStroke,
            size: 20,
          ),
          trailingIcon: Icons.chevron_right_outlined,
          trailingIconIsMuted: true,
          onTap: () async => _onShowAllTripMemories(context, improved: false),
        ),
        MenuItemWidgetNew(
          title: "Show all improved trip memories",
          leadingIconWidget: Icon(
            Icons.travel_explore_outlined,
            color: getEnteColorScheme(context).menuItemIconStroke,
            size: 20,
          ),
          trailingIcon: Icons.chevron_right_outlined,
          trailingIconIsMuted: true,
          onTap: () async => _onShowAllTripMemories(context, improved: true),
        ),
        MenuItemWidgetNew(
          title: "Sync person mappings",
          leadingIconWidget: _buildIconWidget(
            context,
            HugeIcons.strokeRoundedUserSettings01,
          ),
          trailingIcon: Icons.chevron_right_outlined,
          trailingIconIsMuted: true,
          onTap: () async => _onSyncPersonMappings(context),
        ),
      ],
    );
  }

  Widget _buildVectorIndexCard(BuildContext context) {
    return FutureBuilder<Map<rust.Index, _VectorIndexStatus>>(
      future: _getVectorIndexStatuses(),
      builder: (context, snapshot) {
        final statuses = snapshot.data;
        return SettingsGroupedCard(
          children: [
            for (final index in rust.Index.values)
              MenuItemWidgetNew(
                title: _vectorIndexTitle(index),
                subText: statuses == null
                    ? null
                    : "${statuses[index]!.vectors} vectors",
                leadingIconWidget: _buildIconWidget(
                  context,
                  _vectorIndexIcon(index),
                ),
                trailingWidget: _buildVectorIndexStatusWidget(
                  context,
                  status: statuses?[index],
                  hasError: snapshot.hasError,
                ),
              ),
            MenuItemWidgetNew(
              title: "Refresh vector index status",
              leadingIconWidget: _buildIconWidget(
                context,
                HugeIcons.strokeRoundedReload,
              ),
              trailingIcon: Icons.chevron_right_outlined,
              trailingIconIsMuted: true,
              onTap: () async {
                if (mounted) {
                  setState(() {});
                }
              },
            ),
          ],
        );
      },
    );
  }

  static String _vectorIndexTitle(rust.Index index) => switch (index) {
    rust.Index.clip => "Clip vector index",
    rust.Index.clusterCentroid => "Cluster centroid vector index",
  };

  static List<List<dynamic>> _vectorIndexIcon(rust.Index index) =>
      switch (index) {
        rust.Index.clip => HugeIcons.strokeRoundedAiSearch,
        rust.Index.clusterCentroid => HugeIcons.strokeRoundedUserMultiple,
      };

  Widget _buildVectorIndexStatusWidget(
    BuildContext context, {
    required _VectorIndexStatus? status,
    required bool hasError,
  }) {
    final colorScheme = getEnteColorScheme(context);
    final textTheme = getEnteTextTheme(context);
    final String label;
    final Color color;

    if (hasError) {
      label = "Error";
      color = colorScheme.warning500;
    } else if (status == null) {
      label = "Loading";
      color = colorScheme.textMuted;
    } else {
      label = switch (status.state) {
        rust.FillState.filled => "Filled",
        rust.FillState.filling => "Filling",
        rust.FillState.stale => "Stale",
      };
      color = status.state == rust.FillState.filled
          ? colorScheme.greenBase
          : colorScheme.warning500;
    }

    return Text(label, style: textTheme.miniBold.copyWith(color: color));
  }

  Future<Map<rust.Index, _VectorIndexStatus>> _getVectorIndexStatuses() async {
    final store = await RustMLDataDB.instance.store;
    return {
      for (final index in rust.Index.values)
        index: (
          state: await store.fillState(index: index),
          vectors: (await store.stats(index: index)).liveCount,
        ),
    };
  }

  Widget _buildThresholdsCard(BuildContext context) {
    return SettingsGroupedCard(
      children: [
        _buildThresholdItem(
          context,
          title: "Auto-merge threshold",
          description:
              "Used when creating a new person to auto-merge nearby clusters.",
          value: _autoMergeThreshold,
          defaultValue: PersonService.kDefaultAutoMergeThreshold,
          persistValue: _persistAutoMergeThreshold,
          onPersistChanged: _onAutoMergePersistChanged,
          min: _autoMergeMin,
          max: _autoMergeMax,
          onChanged: _updateAutoMergeThreshold,
        ),
        _buildThresholdItem(
          context,
          title: "Default clustering distance",
          description:
              "Default distance threshold used for clustering new faces.",
          value: _defaultClusteringDistance,
          defaultValue: FaceClusteringService.kRecommendedDistanceThreshold,
          persistValue: _persistDefaultClusteringDistance,
          onPersistChanged: _onClusteringPersistChanged,
          min: _clusteringMin,
          max: _clusteringMax,
          onChanged: _updateDefaultClusteringDistance,
        ),
      ],
    );
  }

  Widget _buildThresholdItem(
    BuildContext context, {
    required String title,
    required String description,
    required double value,
    required double defaultValue,
    required bool persistValue,
    required ValueChanged<bool> onPersistChanged,
    required double min,
    required double max,
    required ValueChanged<double> onChanged,
  }) {
    final textTheme = getEnteTextTheme(context);
    final clampedValue = _clampThreshold(value, min, max);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: textTheme.smallBold),
          const SizedBox(height: 4),
          Text(description, style: textTheme.miniMuted),
          const SizedBox(height: 12),
          Row(
            children: [
              Text(min.toStringAsFixed(2), style: textTheme.mini),
              Expanded(
                child: Slider(
                  value: clampedValue,
                  min: min,
                  max: max,
                  divisions: _divisionsForRange(min, max),
                  onChanged: (value) {
                    onChanged(_roundToStep(value));
                  },
                ),
              ),
              Text(max.toStringAsFixed(2), style: textTheme.mini),
            ],
          ),
          Text(
            "Current: ${clampedValue.toStringAsFixed(2)}",
            style: textTheme.miniMuted,
          ),
          const SizedBox(height: 4),
          Text(
            "Default: ${defaultValue.toStringAsFixed(2)}",
            style: textTheme.miniMuted,
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("Save on device", style: textTheme.mini),
              ToggleSwitchWidget(
                value: () => persistValue,
                onChanged: () async {
                  onPersistChanged(!persistValue);
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  int _divisionsForRange(double min, double max) {
    return ((max - min) / _thresholdStep).round();
  }

  double _roundToStep(double value) {
    return (value / _thresholdStep).round() * _thresholdStep;
  }

  double _clampThreshold(double value, double min, double max) {
    return value.clamp(min, max).toDouble();
  }

  void _updateAutoMergeThreshold(double value) {
    final rounded = _roundToStep(value);
    PersonService.autoMergeThreshold = rounded;
    if (_persistAutoMergeThreshold) {
      unawaited(localSettings.setAutoMergeThresholdOverride(rounded));
    }
    setState(() {
      _autoMergeThreshold = rounded;
    });
  }

  Future<void> _onAutoMergePersistChanged(bool value) async {
    setState(() {
      _persistAutoMergeThreshold = value;
    });
    if (value) {
      await localSettings.setAutoMergeThresholdOverride(_autoMergeThreshold);
    }
  }

  void _updateDefaultClusteringDistance(double value) {
    final rounded = _roundToStep(value);
    FaceClusteringService.defaultDistanceThreshold = rounded;
    if (_persistDefaultClusteringDistance) {
      unawaited(localSettings.setDefaultClusteringDistanceOverride(rounded));
    }
    setState(() {
      _defaultClusteringDistance = rounded;
    });
  }

  Future<void> _onClusteringPersistChanged(bool value) async {
    setState(() {
      _persistDefaultClusteringDistance = value;
    });
    if (value) {
      await localSettings.setDefaultClusteringDistanceOverride(
        _defaultClusteringDistance,
      );
    }
  }

  Widget _buildResetActionsCard(BuildContext context) {
    return SettingsGroupedCard(
      children: [
        if (RewindEdition.isAvailable(DateTime.now())) ...[
          MenuItemWidgetNew(
            title: "Recompute Ente Rewind",
            leadingIconWidget: _buildIconWidget(
              context,
              HugeIcons.strokeRoundedReload,
            ),
            trailingIcon: Icons.chevron_right_outlined,
            trailingIconIsMuted: true,
            onTap: () async => _onRecomputeRewind(context),
          ),
          MenuItemWidgetNew(
            title: "Export Ente Rewind request",
            leadingIconWidget: _buildIconWidget(
              context,
              HugeIcons.strokeRoundedFileExport,
            ),
            trailingIcon: Icons.chevron_right_outlined,
            trailingIconIsMuted: true,
            onTap: () async => _onExportRewindSnapshot(context),
          ),
          MenuItemWidgetNew(
            title: "Open Ente Rewind gallery",
            leadingIconWidget: _buildIconWidget(
              context,
              HugeIcons.strokeRoundedPlay,
            ),
            trailingIcon: Icons.chevron_right_outlined,
            trailingIconIsMuted: true,
            onTap: () async => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const RewindGalleryPage(),
              ),
            ),
          ),
        ],
        MenuItemWidgetNew(
          title: "Clear memories cache",
          leadingIconWidget: _buildIconWidget(
            context,
            HugeIcons.strokeRoundedDelete02,
          ),
          trailingIcon: Icons.chevron_right_outlined,
          trailingIconIsMuted: true,
          onTap: () async => _onClearMemoriesCache(context),
        ),
        MenuItemWidgetNew(
          title: "Reset faces feedback",
          leadingIconWidget: _buildIconWidget(
            context,
            HugeIcons.strokeRoundedUserRemove01,
          ),
          trailingIcon: Icons.chevron_right_outlined,
          trailingIconIsMuted: true,
          onTap: () async => _onResetFacesFeedback(context),
        ),
        MenuItemWidgetNew(
          title: "Reset faces feedback and clustering",
          leadingIconWidget: _buildIconWidget(
            context,
            HugeIcons.strokeRoundedUserRemove02,
          ),
          trailingIcon: Icons.chevron_right_outlined,
          trailingIconIsMuted: true,
          onTap: () async => _onResetFacesAndClustering(context),
        ),
        MenuItemWidgetNew(
          title: "Reset all local faces",
          leadingIconWidget: _buildIconWidget(
            context,
            HugeIcons.strokeRoundedFaceId,
          ),
          trailingIcon: Icons.chevron_right_outlined,
          trailingIconIsMuted: true,
          onTap: () async => _onResetAllLocalFaces(context),
        ),
        MenuItemWidgetNew(
          title: "Reset all local clip",
          leadingIconWidget: _buildIconWidget(
            context,
            HugeIcons.strokeRoundedAiSearch,
          ),
          trailingIcon: Icons.chevron_right_outlined,
          trailingIconIsMuted: true,
          onTap: () async => _onResetAllLocalClip(context),
        ),
        if (MLDataDB.isRustBackend)
          for (final index in rust.Index.values)
            MenuItemWidgetNew(
              title: "Rebuild ${_vectorIndexTitle(index).toLowerCase()}",
              leadingIconWidget: _buildIconWidget(
                context,
                _vectorIndexIcon(index),
              ),
              trailingIcon: Icons.chevron_right_outlined,
              trailingIconIsMuted: true,
              onTap: () async => _onRebuildVectorIndex(context, index),
            ),
      ],
    );
  }

  Widget _buildIconWidget(BuildContext context, List<List<dynamic>> icon) {
    final colorScheme = getEnteColorScheme(context);
    return HugeIcon(
      icon: icon,
      color: colorScheme.menuItemIconStroke,
      size: 20,
    );
  }

  Future<void> _onMLConsentChanged() async {
    try {
      final oldMlConsent = hasGrantedMLConsent;
      final mlConsent = !oldMlConsent;
      await setMLConsent(mlConsent);
      logger.info('ML consent turned ${mlConsent ? 'on' : 'off'}');
      if (!mlConsent) {
        MLService.instance.stopActiveRun(MlStopReason.manual);
        unawaited(MLIndexingIsolate.instance.cleanupLocalIndexingModels());
      } else {
        await MLService.instance.init();
        await SemanticSearchService.instance.init();
        unawaited(MLService.instance.runAllML(force: true));
      }
      if (mounted) {
        setState(() {});
      }
    } catch (e, s) {
      logger.warning('indexing failed ', e, s);
      if (mounted) {
        await showGenericErrorDialog(context: context, error: e);
      }
    }
  }

  Future<void> _onRemoteFetchChanged() async {
    try {
      await localSettings.toggleRemoteFetch();
      logger.info(
        'Remote fetch is turned ${localSettings.remoteFetchEnabled ? 'on' : 'off'}',
      );
      if (mounted) {
        setState(() {});
      }
    } catch (e, s) {
      logger.warning('Remote fetch toggle failed ', e, s);
      if (mounted) {
        await showGenericErrorDialog(context: context, error: e);
      }
    }
  }

  Future<void> _onLocalIndexingChanged() async {
    final localIndexing = await localSettings.toggleLocalMLIndexing();
    if (localIndexing) {
      unawaited(MLService.instance.runAllML(force: true));
    } else {
      MLService.instance.stopActiveRun(MlStopReason.manual);
      unawaited(MLIndexingIsolate.instance.cleanupLocalIndexingModels());
    }
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _onAutoIndexingChanged() async {
    try {
      MLService.instance.debugIndexingDisabled =
          !MLService.instance.debugIndexingDisabled;
      if (MLService.instance.debugIndexingDisabled) {
        MLService.instance.stopActiveRun(MlStopReason.manual);
      } else {
        unawaited(MLService.instance.runAllML());
      }
      if (mounted) {
        setState(() {});
      }
    } catch (e, s) {
      logger.warning('debugIndexingDisabled toggle failed ', e, s);
      if (mounted) {
        await showGenericErrorDialog(context: context, error: e);
      }
    }
  }

  Future<void> _onRunMLDuringInteractionChanged() async {
    try {
      final enabled = !localSettings.runMLDuringInteractionOverride;
      await computeController.setMLInteractionOverride(turnOn: enabled);
      logger.info(
        'run ML during interaction is turned ${enabled ? 'on' : 'off'}',
      );
      if (mounted) {
        setState(() {});
      }
    } catch (e, s) {
      logger.warning('run ML during interaction toggle failed ', e, s);
      if (mounted) {
        await showGenericErrorDialog(context: context, error: e);
      }
    }
  }

  Future<void> _onPetRecognitionChanged() async {
    try {
      await localSettings.togglePetRecognition();
      // Invalidate cached runtime args so pet model paths are rebuilt
      // with the new toggle state on the next indexing run.
      await MLIndexingIsolate.instance.releaseRustRuntime();
      MLModelDownloadService.instance.invalidateModelDownloadCache();
      logger.info(
        'Pet recognition is turned ${localSettings.petRecognitionEnabled ? 'on' : 'off'}',
      );
      if (mounted) {
        setState(() {});
      }
    } catch (e, s) {
      logger.warning('Pet recognition toggle failed ', e, s);
      if (mounted) {
        await showGenericErrorDialog(context: context, error: e);
      }
    }
  }

  Future<void> _onTriggerRunML(BuildContext context) async {
    try {
      MLService.instance.debugIndexingDisabled = false;
      unawaited(MLService.instance.runAllML());
      showShortToast(context, "ML started");
    } catch (e, s) {
      logger.warning('indexAndClusterAll failed ', e, s);
      await showGenericErrorDialog(context: context, error: e);
    }
  }

  Future<void> _onTriggerRunIndexing(BuildContext context) async {
    try {
      MLService.instance.debugIndexingDisabled = false;
      unawaited(
        MLService.instance.fetchAndIndexAllImages(mode: MLMode.enteGallery),
      );
      showShortToast(context, "Indexing started");
    } catch (e, s) {
      logger.warning('indexing failed ', e, s);
      await showGenericErrorDialog(context: context, error: e);
    }
  }

  Future<void> _onShowProcessLockState(BuildContext context) async {
    try {
      final description = await MlProcessLock.instance.describeState();
      if (!context.mounted) return;
      showShortToast(context, description);
    } catch (e, s) {
      logger.warning('fetching ml process lock state failed', e, s);
      if (!context.mounted) return;
      await showGenericErrorDialog(context: context, error: e);
    }
  }

  Future<void> _onTriggerClustering(BuildContext context) async {
    try {
      await PersonService.instance.sync();
      MLService.instance.debugIndexingDisabled = false;
      final attempt = await MLService.instance.clusterAllImages();
      if (!context.mounted) return;
      if (attempt != MlLockAttempt.ran) {
        showShortToast(context, "Denied (${attempt.name})");
        return;
      }
      Bus.instance.fire(PeopleChangedEvent());
      showShortToast(context, "Done");
    } catch (e, s) {
      logger.warning('clustering failed ', e, s);
      if (!context.mounted) return;
      await showGenericErrorDialog(context: context, error: e);
    }
  }

  Future<void> _onUpdateDiscover(BuildContext context) async {
    try {
      await magicCacheService.updateCache(forced: true);
      if (!context.mounted) return;
      showShortToast(context, "Done");
    } catch (e, s) {
      logger.warning('Update discover failed', e, s);
      if (!context.mounted) return;
      await showGenericErrorDialog(context: context, error: e);
    }
  }

  Future<void> _onUpdateMemories(BuildContext context) async {
    try {
      final now = DateTime.now();
      await memoriesCacheService.updateCache(forced: true);
      final duration = DateTime.now().difference(now);
      if (!context.mounted) return;
      showShortToast(context, "Done in ${duration.inSeconds} seconds");
    } catch (e, s) {
      logger.warning('Update memories failed', e, s);
      if (!context.mounted) return;
      await showGenericErrorDialog(context: context, error: e);
    }
  }

  Future<void> _onShowAllMemoriesDebug(BuildContext context) async {
    await routeToPage(context, const MemoriesDebugPage());
  }

  Future<void> _onShowAllTripMemories(
    BuildContext context, {
    required bool improved,
  }) async {
    await routeToPage(
      context,
      MemoriesDebugPage(
        title: improved ? "Improved trip memories" : "Legacy trip memories",
        loadMemories: (calculationTime) => smartMemoriesService
            .debugCalcAllTripMemories(calculationTime, improved: improved),
      ),
    );
  }

  Future<void> _onSyncPersonMappings(BuildContext context) async {
    try {
      await PersonService.instance.sync();
      if (!context.mounted) return;
      showShortToast(context, "Done");
    } catch (e, s) {
      logger.warning('sync person mappings failed ', e, s);
      if (!context.mounted) return;
      await showGenericErrorDialog(context: context, error: e);
    }
  }

  Future<void> _onRecomputeRewind(BuildContext context) async {
    try {
      await rewindService.recompute();
      final state = rewindService.state.value;
      if (!context.mounted) return;
      showShortToast(
        context,
        state == null
            ? "Ente Rewind not computed"
            : "Ente Rewind ${state.status.runtimeType}, coverage ${state.mlCoverage}",
      );
    } catch (e, s) {
      logger.warning('Ente Rewind recompute failed', e, s);
      if (!context.mounted) return;
      await showGenericErrorDialog(context: context, error: e);
    }
  }

  Future<void> _onExportRewindSnapshot(BuildContext context) async {
    try {
      final snapshot = await exportRewindSnapshot();
      if (!context.mounted) return;
      showShortToast(context, "Ente Rewind request: $snapshot");
    } catch (e, s) {
      logger.warning('Ente Rewind snapshot export failed', e, s);
      if (!context.mounted) return;
      await showGenericErrorDialog(context: context, error: e);
    }
  }

  Future<void> _onClearMemoriesCache(BuildContext context) async {
    try {
      final now = DateTime.now();
      await memoriesCacheService.clearMemoriesCache();
      final duration = DateTime.now().difference(now);
      if (!context.mounted) return;
      showShortToast(context, "Done in ${duration.inSeconds} seconds");
    } catch (e, s) {
      logger.warning('Clear memories cache failed', e, s);
      if (!context.mounted) return;
      await showGenericErrorDialog(context: context, error: e);
    }
  }

  Future<void> _onResetFacesFeedback(BuildContext context) async {
    await showChoiceDialog(
      context,
      title: "Are you sure?",
      body:
          "This will drop all people and their related feedback stored locally.",
      firstButtonLabel: "Yes, confirm",
      firstButtonOnTap: () async {
        try {
          await mlDataDB.dropFacesFeedbackTables();
          Bus.instance.fire(PeopleChangedEvent());
          if (!context.mounted) return;
          showShortToast(context, "Done");
        } catch (e, s) {
          logger.warning('reset feedback failed ', e, s);
          if (!context.mounted) return;
          await showGenericErrorDialog(context: context, error: e);
        }
      },
    );
  }

  Future<void> _onResetFacesAndClustering(BuildContext context) async {
    await showChoiceDialog(
      context,
      title: "Are you sure?",
      body:
          "This will delete all people (also from remote), their related feedback and clustering labels.",
      firstButtonLabel: "Yes, confirm",
      firstButtonOnTap: () async {
        try {
          final List<PersonEntity> persons = await PersonService.instance
              .getPersons();
          for (final PersonEntity p in persons) {
            await PersonService.instance.deletePerson(p.remoteID);
          }
          await mlDataDB.dropClustersAndPersonTable();
          Bus.instance.fire(PeopleChangedEvent());
          if (!context.mounted) return;
          showShortToast(context, "Done");
        } catch (e, s) {
          logger.warning('peopleToPersonMapping remove failed ', e, s);
          if (!context.mounted) return;
          await showGenericErrorDialog(context: context, error: e);
        }
      },
    );
  }

  Future<void> _onResetAllLocalFaces(BuildContext context) async {
    await showChoiceDialog(
      context,
      title: "Are you sure?",
      body:
          "This will drop all local faces data. You will need to again re-index faces.",
      firstButtonLabel: "Yes, confirm",
      firstButtonOnTap: () async {
        try {
          await mlDataDB.dropClustersAndPersonTable(faces: true);
          Bus.instance.fire(PeopleChangedEvent());
          if (!context.mounted) return;
          showShortToast(context, "Done");
        } catch (e, s) {
          logger.warning('drop feedback failed ', e, s);
          if (!context.mounted) return;
          await showGenericErrorDialog(context: context, error: e);
        }
      },
    );
  }

  Future<void> _onResetAllLocalClip(BuildContext context) async {
    await showChoiceDialog(
      context,
      title: "Are you sure?",
      body:
          "You will need to again re-index or fetch all clip image embeddings.",
      firstButtonLabel: "Yes, confirm",
      firstButtonOnTap: () async {
        try {
          await SemanticSearchService.instance.clearIndexes();
          if (!context.mounted) return;
          showShortToast(context, "Done");
        } catch (e, s) {
          logger.warning('drop clip embeddings failed ', e, s);
          if (!context.mounted) return;
          await showGenericErrorDialog(context: context, error: e);
        }
      },
    );
  }

  Future<void> _onRebuildVectorIndex(
    BuildContext context,
    rust.Index index,
  ) async {
    await showChoiceDialog(
      context,
      title: "Are you sure?",
      body:
          "This will rebuild the ${_vectorIndexTitle(index).toLowerCase()} from the database. Compute is paused while the rebuild runs.",
      firstButtonLabel: "Yes, confirm",
      firstButtonOnTap: () async {
        try {
          await switch (index) {
            rust.Index.clip => mlDataDB.checkMigrateFillClipVectorDB(
              force: true,
            ),
            rust.Index.clusterCentroid =>
              mlDataDB.checkMigrateFillClusterCentroidVectorDB(force: true),
          };
          if (!context.mounted) return;
          showShortToast(context, "Done");
          if (mounted) {
            setState(() {});
          }
        } catch (e, s) {
          logger.warning('rebuild $index failed ', e, s);
          if (!context.mounted) return;
          await showGenericErrorDialog(context: context, error: e);
        }
      },
    );
  }
}
