import "dart:async";

import "package:flutter/material.dart";
import "package:logging/logging.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/db/ml/base.dart";
import "package:photos/db/ml/db.dart";
import "package:photos/events/people_changed_event.dart";
import "package:photos/service_locator.dart";
import "package:photos/services/machine_learning/face_ml/face_clustering/face_clustering_service.dart";
import "package:photos/services/machine_learning/face_ml/person/person_service.dart";
import "package:photos/services/machine_learning/ml_indexing_isolate.dart";
import "package:photos/services/machine_learning/ml_models_overview.dart";
import "package:photos/services/machine_learning/semantic_search/semantic_search_service.dart";
import "package:photos/theme/ente_theme.dart";
import "package:photos/ui/components/buttons/button_widget.dart";
import "package:photos/ui/components/captioned_text_widget.dart";
import "package:photos/ui/components/menu_item_widget/menu_item_widget.dart";
import "package:photos/ui/components/models/button_type.dart";
import "package:photos/ui/components/settings/settings_grouped_card.dart";
import "package:photos/ui/components/title_bar_title_widget.dart";
import "package:photos/ui/components/title_bar_widget.dart";
import "package:photos/ui/components/toggle_switch_widget.dart";
import "package:photos/ui/notification/toast.dart";
import "package:photos/utils/dialog_util.dart";

final Logger _logger = Logger("MLUserDeveloperOptions");

class MLUserDeveloperOptions extends StatefulWidget {
  final bool mlIsEnabled;
  const MLUserDeveloperOptions({super.key, this.mlIsEnabled = true});

  @override
  State<MLUserDeveloperOptions> createState() => _MLUserDeveloperOptionsState();
}

class _MLUserDeveloperOptionsState extends State<MLUserDeveloperOptions> {
  late final IMLDataDB<int> mlDataDB = MLDataDB.instance;
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
    return Scaffold(
      body: CustomScrollView(
        primary: false,
        slivers: <Widget>[
          const TitleBarWidget(
            flexibleSpaceTitle: TitleBarTitleWidget(title: "ML debug options"),
          ),
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (delegateBuildContext, index) => Padding(
                padding: const EdgeInsets.only(left: 16, right: 16),
                child: Column(
                  children: [
                    Text(
                      "Only use if you know what you're doing",
                      textAlign: TextAlign.left,
                      style: getEnteTextTheme(context).body.copyWith(
                        color: getEnteColorScheme(context).textMuted,
                      ),
                    ),
                    const SizedBox(height: 48),
                    widget.mlIsEnabled
                        ? ButtonWidget(
                            buttonType: ButtonType.neutral,
                            labelText: "Purge empty indices",
                            onTap: () async {
                              await deleteEmptyIndices(context);
                            },
                          )
                        : const SizedBox(),
                    widget.mlIsEnabled
                        ? const SizedBox(height: 24)
                        : const SizedBox(),
                    widget.mlIsEnabled
                        ? ButtonWidget(
                            buttonType: ButtonType.neutral,
                            labelText: "Reset all local ML",
                            onTap: () async {
                              await deleteAllLocalML(context);
                            },
                          )
                        : const SizedBox(),
                    widget.mlIsEnabled
                        ? const SizedBox(height: 24)
                        : const SizedBox(),
                    widget.mlIsEnabled
                        ? MenuItemWidget(
                            captionedTextWidget: const CaptionedTextWidget(
                              title: "Remote fetch",
                            ),
                            menuItemColor: colorScheme.fillFaint,
                            trailingWidget: ToggleSwitchWidget(
                              value: () => localSettings.remoteFetchEnabled,
                              onChanged: () async {
                                try {
                                  await localSettings.toggleRemoteFetch();
                                  _logger.info(
                                    'Remote fetch is turned ${localSettings.remoteFetchEnabled ? 'on' : 'off'}',
                                  );
                                  if (mounted) {
                                    setState(() {});
                                  }
                                } catch (e, s) {
                                  _logger.warning(
                                    'Remote fetch toggle failed ',
                                    e,
                                    s,
                                  );
                                  if (!context.mounted) return;
                                  await showGenericErrorDialog(
                                    context: context,
                                    error: e,
                                  );
                                }
                              },
                            ),
                            singleBorderRadius: 8,
                            alignCaptionedTextToLeft: true,
                            isBottomBorderRadiusRemoved: true,
                            isGestureDetectorDisabled: true,
                          )
                        : const SizedBox(),
                    widget.mlIsEnabled
                        ? const SizedBox(height: 24)
                        : const SizedBox.shrink(),
                    widget.mlIsEnabled
                        ? MenuItemWidget(
                            captionedTextWidget: const CaptionedTextWidget(
                              title: "Run ML on interactions",
                            ),
                            menuItemColor: colorScheme.fillFaint,
                            trailingWidget: ToggleSwitchWidget(
                              value: () =>
                                  localSettings.runMLDuringInteractionOverride,
                              onChanged: () async {
                                try {
                                  final enabled = !localSettings
                                      .runMLDuringInteractionOverride;
                                  await computeController
                                      .setMLInteractionOverride(
                                        turnOn: enabled,
                                      );
                                  _logger.info(
                                    'run ML during interaction is turned ${enabled ? 'on' : 'off'}',
                                  );
                                  if (mounted) {
                                    setState(() {});
                                  }
                                } catch (e, s) {
                                  _logger.warning(
                                    'run ML during interaction toggle failed ',
                                    e,
                                    s,
                                  );
                                  if (!context.mounted) return;
                                  await showGenericErrorDialog(
                                    context: context,
                                    error: e,
                                  );
                                }
                              },
                            ),
                            singleBorderRadius: 8,
                            alignCaptionedTextToLeft: true,
                            isBottomBorderRadiusRemoved: true,
                            isGestureDetectorDisabled: true,
                          )
                        : const SizedBox.shrink(),
                    widget.mlIsEnabled
                        ? const SizedBox(height: 24)
                        : const SizedBox.shrink(),
                    widget.mlIsEnabled
                        ? _buildThresholdsCard(context)
                        : const SizedBox.shrink(),
                    widget.mlIsEnabled
                        ? const SizedBox(height: 24)
                        : const SizedBox.shrink(),
                    ButtonWidget(
                      buttonType: ButtonType.neutral,
                      labelText: "Load face detection model",
                      onTap: () async {
                        try {
                          await MLIndexingIsolate.instance.debugLoadSingleModel(
                            MLModels.faceDetection,
                          );
                        } catch (e, s) {
                          _logger.severe(
                            "Could not load face detection model",
                            e,
                            s,
                          );
                          if (!context.mounted) return;
                          await showGenericErrorDialog(
                            context: context,
                            error: e,
                          );
                        }
                      },
                    ),
                    const SizedBox(height: 24),
                    ButtonWidget(
                      buttonType: ButtonType.neutral,
                      labelText: "Load face recognition model",
                      onTap: () async {
                        try {
                          await MLIndexingIsolate.instance.debugLoadSingleModel(
                            MLModels.faceEmbedding,
                          );
                        } catch (e, s) {
                          _logger.severe(
                            "Could not load face detection model",
                            e,
                            s,
                          );
                          if (!context.mounted) return;
                          await showGenericErrorDialog(
                            context: context,
                            error: e,
                          );
                        }
                      },
                    ),
                    const SizedBox(height: 24),
                    ButtonWidget(
                      buttonType: ButtonType.neutral,
                      labelText: "Load clip image model",
                      onTap: () async {
                        try {
                          await MLIndexingIsolate.instance.debugLoadSingleModel(
                            MLModels.clipImageEncoder,
                          );
                        } catch (e, s) {
                          _logger.severe(
                            "Could not load face detection model",
                            e,
                            s,
                          );
                          if (!context.mounted) return;
                          await showGenericErrorDialog(
                            context: context,
                            error: e,
                          );
                        }
                      },
                    ),
                    const SizedBox(height: 24),
                    ButtonWidget(
                      buttonType: ButtonType.neutral,
                      labelText: "Load clip text model",
                      onTap: () async {
                        try {
                          await MLIndexingIsolate.instance.debugLoadSingleModel(
                            MLModels.clipTextEncoder,
                          );
                        } catch (e, s) {
                          _logger.severe(
                            "Could not load face detection model",
                            e,
                            s,
                          );
                          if (!context.mounted) return;
                          await showGenericErrorDialog(
                            context: context,
                            error: e,
                          );
                        }
                      },
                    ),
                    const SafeArea(child: SizedBox(height: 12)),
                  ],
                ),
              ),
              childCount: 1,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> deleteEmptyIndices(BuildContext context) async {
    try {
      final Set<int> emptyFileIDs = await mlDataDB.getErroredFileIDs();
      await mlDataDB.deleteFaceIndexForFiles(emptyFileIDs.toList());
      await mlDataDB.deleteClipEmbeddings(emptyFileIDs.toList());
      await mlDataDB.deletePetDataForFiles(emptyFileIDs.toList());
      if (!context.mounted) return;
      showShortToast(context, "Deleted ${emptyFileIDs.length} entries");
    } catch (e) {
      if (!context.mounted) return;
      // ignore: unawaited_futures
      showGenericErrorDialog(context: context, error: e);
    }
  }

  Future<void> deleteAllLocalML(BuildContext context) async {
    try {
      await mlDataDB.dropClustersAndPersonTable(faces: true);
      await SemanticSearchService.instance.clearIndexes();
      Bus.instance.fire(PeopleChangedEvent());
      if (!context.mounted) return;
      showShortToast(context, "All local ML cleared");
    } catch (e) {
      if (!context.mounted) return;
      // ignore: unawaited_futures
      showGenericErrorDialog(context: context, error: e);
    }
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
}
