import 'dart:async';

import "package:ente_components/ente_components.dart";
import "package:ente_strings/ente_strings.dart";
import "package:flutter/foundation.dart";
import 'package:flutter/material.dart';
import "package:hugeicons/hugeicons.dart";
import 'package:logging/logging.dart';
import 'package:photos/core/configuration.dart';
import 'package:photos/core/event_bus.dart';
import "package:photos/db/files_db.dart";
import "package:photos/events/people_changed_event.dart";
import 'package:photos/events/subscription_purchased_event.dart';
import "package:photos/models/file/file.dart";
import 'package:photos/models/gallery_type.dart';
import 'package:photos/models/selected_files.dart';
import "package:photos/service_locator.dart" show isLocalGalleryMode;
import 'package:photos/services/collections_service.dart';
import "package:photos/services/machine_learning/face_ml/feedback/cluster_feedback.dart";
import "package:photos/services/machine_learning/ml_result.dart";
import 'package:photos/ui/actions/collection/collection_sharing_actions.dart';
import 'package:photos/ui/components/buttons/button_widget.dart';
import 'package:photos/ui/sharing/share_person_sheet.dart';
import "package:photos/ui/viewer/gallery/gallery_app_bar_actions.dart";
import "package:photos/ui/viewer/gallery/gallery_app_bar_config.dart";
import "package:photos/ui/viewer/gallery/gallery_app_bar_widget.dart";
import 'package:photos/ui/viewer/gallery/state/gallery_files_inherited_widget.dart';
import "package:photos/ui/viewer/people/cluster_breakup_page.dart";
import "package:photos/ui/viewer/people/cluster_page.dart";
import "package:photos/ui/viewer/people/person_face_widget.dart";
import "package:photos/utils/dialog_util.dart";

class ClusterAppBar extends StatefulWidget {
  static GalleryAppBarConfig sliverConfig(
    GalleryType type,
    String? title,
    SelectedFiles selectedFiles,
    String clusterID, {
    required List<EnteFile> files,
    Key? coverAppBarKey,
    String? coverHeroTag,
    bool memoryLaneReady = false,
    Future<void> Function()? onMemoryLaneTap,
  }) {
    final config = GalleryAppBarWidget.sliverConfig(
      type,
      title,
      selectedFiles,
      coverWidget: files.isEmpty
          ? null
          : PersonFaceWidget(clusterID: clusterID),
    );
    return GalleryAppBarConfig(
      extendBodyForCollapse: config.extendBodyForCollapse,
      sliverBuilder: (_) => ClusterAppBar._(
        type,
        title,
        selectedFiles,
        clusterID,
        memoryLaneReady,
        onMemoryLaneTap,
        files,
        coverAppBarKey,
        coverHeroTag,
      ),
      geometryBuilder: config.geometryBuilder,
    );
  }

  final List<EnteFile> files;
  final Key? coverAppBarKey;
  final String? coverHeroTag;
  final GalleryType type;
  final String? title;
  final SelectedFiles selectedFiles;
  final String clusterID;
  final bool memoryLaneReady;
  final Future<void> Function()? onMemoryLaneTap;

  const ClusterAppBar._(
    this.type,
    this.title,
    this.selectedFiles,
    this.clusterID,
    this.memoryLaneReady,
    this.onMemoryLaneTap,
    this.files,
    this.coverAppBarKey,
    this.coverHeroTag,
  );

  @override
  State<ClusterAppBar> createState() => _AppBarWidgetState();
}

enum ClusterPopupAction {
  setCover,
  breakupCluster,
  breakupClusterDebug,
  ignore,
  memoryLane,
}

class _AppBarWidgetState extends State<ClusterAppBar> {
  final _logger = Logger("_AppBarWidgetState");
  late StreamSubscription _userAuthEventSubscription;
  late Function() _selectedFilesListener;
  String? _appBarTitle;
  late CollectionActions collectionActions;
  final GlobalKey shareButtonKey = GlobalKey();
  bool isQuickLink = false;
  late GalleryType galleryType;

  @override
  void initState() {
    super.initState();
    _selectedFilesListener = () {
      setState(() {});
    };
    collectionActions = CollectionActions(CollectionsService.instance);
    widget.selectedFiles.addListener(_selectedFilesListener);
    _userAuthEventSubscription = Bus.instance
        .on<SubscriptionPurchasedEvent>()
        .listen((event) {
          setState(() {});
        });
    _appBarTitle = widget.title;
    galleryType = widget.type;
  }

  @override
  void dispose() {
    _userAuthEventSubscription.cancel();
    widget.selectedFiles.removeListener(_selectedFilesListener);
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant ClusterAppBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.title != widget.title) {
      _appBarTitle = widget.title;
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUserID = Configuration.instance.getUserID();
    final shareableFiles =
        widget.selectedFiles.files.isEmpty &&
            !isLocalGalleryMode &&
            Configuration.instance.hasConfiguredAccount()
        ? GalleryFilesState.maybeOf(context)?.galleryFilesOrNull?.where(
            (file) =>
                file.uploadedFileID != null && file.ownerID == currentUserID,
          )
        : null;
    final hasShareableFiles = shareableFiles?.isNotEmpty ?? false;
    return GalleryAppBarWidget.sliverConfig(
      widget.type,
      _appBarTitle,
      widget.selectedFiles,
      files: widget.files,
      coverAppBarKey: widget.coverAppBarKey,
      coverWidget: widget.files.isEmpty
          ? null
          : PersonFaceWidget(
              clusterID: widget.clusterID,
              cachedPixelWidth:
                  (MediaQuery.sizeOf(context).width *
                          MediaQuery.devicePixelRatioOf(context))
                      .ceil(),
            ),
      coverHeroTag: widget.coverHeroTag,
      actionsBuilder: ({required onCover, foregroundColor}) =>
          _getDefaultActions(
            context,
            onCover: onCover,
            foregroundColor: foregroundColor,
            shareableFiles: hasShareableFiles ? shareableFiles : null,
          ),
    ).buildSliver(context);
  }

  List<Widget> _getDefaultActions(
    BuildContext context, {
    required bool onCover,
    Color? foregroundColor,
    required Iterable<EnteFile>? shareableFiles,
  }) {
    final hasAccount = Configuration.instance.hasConfiguredAccount();
    final List<Widget> actions = <Widget>[];
    if (widget.selectedFiles.files.isNotEmpty) {
      return actions;
    }

    if (!isLocalGalleryMode && hasAccount) {
      if (shareableFiles != null) {
        actions.add(
          IconButtonComponent(
            key: shareButtonKey,
            icon: HugeIcon(
              icon: HugeIcons.strokeRoundedShare08,
              color: foregroundColor,
            ),
            variant: onCover
                ? IconButtonComponentVariant.unfilled
                : IconButtonComponentVariant.primary,
            size: onCover ? kMinInteractiveDimension : 36,
            iconSize: onCover ? IconSizes.medium : IconSizes.small,
            tooltip: context.strings.share,
            shouldSurfaceExecutionStates: false,
            onTap: () => showSharePersonSheet(
              context,
              files: shareableFiles.toList(),
              shareButtonKey: shareButtonKey,
            ),
          ),
        );
      }
    }

    final List<EntePopupMenuOption<ClusterPopupAction>> items = [
      if (widget.memoryLaneReady && widget.onMemoryLaneTap != null)
        EntePopupMenuOption(
          value: ClusterPopupAction.memoryLane,
          label: context.strings.facesTimelineAppBarTitle,
          leadingWidget: const HugeIcon(
            icon: HugeIcons.strokeRoundedSparkles,
            size: IconSizes.small,
          ),
        ),
      if (!isLocalGalleryMode && hasAccount) ...[
        EntePopupMenuOption(
          value: ClusterPopupAction.ignore,
          label: context.strings.ignorePerson,
          leadingWidget: const HugeIcon(
            icon: HugeIcons.strokeRoundedUserBlock01,
            size: IconSizes.small,
          ),
        ),
        EntePopupMenuOption(
          value: ClusterPopupAction.breakupCluster,
          label: context.strings.mixedGrouping,
          leadingWidget: const HugeIcon(
            icon: HugeIcons.strokeRoundedUserMultiple,
            size: IconSizes.small,
          ),
        ),
        if (kDebugMode)
          const EntePopupMenuOption(
            value: ClusterPopupAction.breakupClusterDebug,
            label: "Debug mixed grouping",
            leadingWidget: HugeIcon(
              icon: HugeIcons.strokeRoundedAiBrain01,
              size: IconSizes.small,
            ),
          ),
      ],
    ];
    if (items.isEmpty) return actions;

    final overflowMenuAction = onCover
        ? galleryAppBarActionsSheetAction
        : galleryAppBarPopupMenuAction;
    actions.add(
      overflowMenuAction<ClusterPopupAction>(
        tooltip: context.strings.more,
        icon: HugeIcon(
          icon: HugeIcons.strokeRoundedMoreVertical,
          color: foregroundColor,
        ),
        optionsBuilder: () => items,
        onSelected: (ClusterPopupAction value) async {
          if (value == ClusterPopupAction.breakupCluster) {
            await _breakUpCluster(context);
          } else if (value == ClusterPopupAction.ignore) {
            await _onIgnoredClusterClicked(context);
          } else if (value == ClusterPopupAction.breakupClusterDebug) {
            await _breakUpClusterDebug(context);
          } else if (value == ClusterPopupAction.memoryLane) {
            await widget.onMemoryLaneTap?.call();
          }
        },
      ),
    );

    return actions;
  }

  Future<void> _onIgnoredClusterClicked(BuildContext context) async {
    final result = await showChoiceDialog(
      context,
      title: context.strings.areYouSureYouWantToIgnoreThisPerson,
      body: context.strings.thePersonGroupsWillNotBeDisplayed,
      firstButtonLabel: context.strings.confirm,
      firstButtonOnTap: () async {
        try {
          await ClusterFeedbackService.instance.ignoreCluster(widget.clusterID);
        } catch (e, s) {
          _logger.severe('Ignoring a cluster failed', e, s);
          rethrow;
        }
      },
    );

    if (!mounted || result?.action != ButtonAction.first) {
      return;
    }

    if (!context.mounted) return;
    Navigator.of(context).pop(ClusterPageResult.ignoredPerson);
  }

  Future<void> _breakUpCluster(BuildContext context) async {
    bool userConfirmed = false;
    List<EnteFile> biggestClusterFiles = [];
    String biggestClusterID = '';
    await showChoiceDialog(
      context,
      title: context.strings.doesGroupContainMultiplePeople,
      body: context.strings.automaticallyAnalyzeAndSplitGrouping,
      firstButtonLabel: context.strings.confirm,
      firstButtonOnTap: () async {
        try {
          final newClusterIDToFaceIDs = await ClusterFeedbackService.instance
              .splitCluster(widget.clusterID);

          biggestClusterID = '';
          int biggestClusterSize = 0;
          for (final MapEntry<String, List<String>> clusterToFaces
              in newClusterIDToFaceIDs.entries) {
            if (clusterToFaces.value.length > biggestClusterSize) {
              biggestClusterSize = clusterToFaces.value.length;
              biggestClusterID = clusterToFaces.key;
            }
          }
          final biggestClusterFileIDs = newClusterIDToFaceIDs[biggestClusterID]!
              .map((e) => getFileIdFromFaceId<int>(e))
              .toList();
          biggestClusterFiles = await FilesDB.instance
              .getFileIDToFileFromIDs(biggestClusterFileIDs)
              .then((mapping) => mapping.values.toList());
          // Keep the replacement gallery in newest-first order.
          biggestClusterFiles.sort(
            (a, b) => b.creationTime!.compareTo(a.creationTime!),
          );

          userConfirmed = true;
        } catch (e, s) {
          _logger.severe('Breakup cluster failed', e, s);
        }
      },
    );
    if (userConfirmed) {
      Bus.instance.fire(PeopleChangedEvent());

      if (!context.mounted) return;
      Navigator.of(context).pop();

      if (!context.mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) =>
              ClusterPage(biggestClusterFiles, clusterID: biggestClusterID),
        ),
      );
    }
  }

  Future<void> _breakUpClusterDebug(BuildContext context) async {
    final breakupResult = await ClusterFeedbackService.instance.breakUpCluster(
      widget.clusterID,
    );

    final Map<String, List<String>> newClusterIDToFaceIDs =
        breakupResult.newClusterIdToFaceIds;

    final allFileIDs = newClusterIDToFaceIDs.values
        .expand((e) => e)
        .map((e) => getFileIdFromFaceId<int>(e))
        .toList();

    final fileIDtoFile = await FilesDB.instance.getFileIDToFileFromIDs(
      allFileIDs,
    );

    final newClusterIDToFiles = newClusterIDToFaceIDs.map(
      (key, value) => MapEntry(
        key,
        value
            .map((faceId) => fileIDtoFile[getFileIdFromFaceId<int>(faceId)]!)
            .toList(),
      ),
    );

    if (!context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) =>
            ClusterBreakupPage(newClusterIDToFiles, context.strings.analysis),
      ),
    );
  }
}
