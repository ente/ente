import 'dart:async';

import "package:ente_components/ente_components.dart";
import "package:flutter/foundation.dart";
import 'package:flutter/material.dart';
import "package:hugeicons/hugeicons.dart";
import 'package:logging/logging.dart';
import 'package:photos/core/configuration.dart';
import 'package:photos/core/event_bus.dart';
import "package:photos/db/files_db.dart";
import 'package:photos/db/ml/base.dart';
import "package:photos/db/ml/db.dart";
import "package:photos/events/people_changed_event.dart";
import 'package:photos/events/subscription_purchased_event.dart';
import "package:photos/generated/l10n.dart";
import "package:photos/models/file/file.dart";
import 'package:photos/models/gallery_type.dart';
import 'package:photos/models/selected_files.dart';
import "package:photos/service_locator.dart" show isLocalGalleryMode;
import 'package:photos/services/collections_service.dart';
import "package:photos/services/machine_learning/face_ml/feedback/cluster_feedback.dart";
import "package:photos/services/machine_learning/ml_result.dart";
import "package:photos/theme/ente_theme.dart";
import 'package:photos/ui/actions/collection/collection_sharing_actions.dart';
import 'package:photos/ui/components/buttons/button_widget.dart';
import "package:photos/ui/viewer/gallery/gallery_app_bar_actions.dart";
import "package:photos/ui/viewer/gallery/gallery_app_bar_config.dart";
import "package:photos/ui/viewer/people/cluster_breakup_page.dart";
import "package:photos/ui/viewer/people/cluster_page.dart";
import "package:photos/utils/dialog_util.dart";

class ClusterAppBar extends StatefulWidget {
  static const double _sliverExpandedHeight = 92.0;

  static GalleryAppBarConfig sliverConfig(
    GalleryType type,
    String? title,
    SelectedFiles selectedFiles,
    String clusterID,
  ) {
    return GalleryAppBarConfig(
      sliverBuilder: (_) =>
          ClusterAppBar._(type, title, selectedFiles, clusterID),
      geometryBuilder: (context) => SliverAppBarComponent.resolveGeometry(
        context,
        expandedHeight: _sliverExpandedHeight,
        collapsedHeight: kToolbarHeight,
      ),
    );
  }

  final GalleryType type;
  final String? title;
  final SelectedFiles selectedFiles;
  final String clusterID;

  const ClusterAppBar._(
    this.type,
    this.title,
    this.selectedFiles,
    this.clusterID,
  );

  @override
  State<ClusterAppBar> createState() => _AppBarWidgetState();
}

enum ClusterPopupAction {
  setCover,
  breakupCluster,
  breakupClusterDebug,
  ignore,
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
  late final IMLDataDB mlDataDB = MLDataDB.instance;

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
    return SliverAppBarComponent(
      title: _appBarTitle ?? "",
      actions: _getDefaultActions(context),
      expandedHeight: ClusterAppBar._sliverExpandedHeight,
      collapsedHeight: kToolbarHeight,
      backgroundColor: getEnteColorScheme(context).backgroundColour,
    );
  }

  List<Widget> _getDefaultActions(BuildContext context) {
    final iconColor = getEnteColorScheme(context).contentLight;
    final List<Widget> actions = <Widget>[];
    // If the user has selected files, don't show any actions
    if (widget.selectedFiles.files.isNotEmpty ||
        isLocalGalleryMode ||
        !Configuration.instance.hasConfiguredAccount()) {
      return actions;
    }

    final List<EntePopupMenuOption<ClusterPopupAction>> items = [
      EntePopupMenuOption(
        value: ClusterPopupAction.ignore,
        label: AppLocalizations.of(context).ignorePerson,
        leadingWidget: galleryAppBarMenuIcon(
          HugeIcons.strokeRoundedUserBlock01,
          iconColor,
        ),
      ),
      EntePopupMenuOption(
        value: ClusterPopupAction.breakupCluster,
        label: AppLocalizations.of(context).mixedGrouping,
        leadingWidget: galleryAppBarMenuIcon(
          HugeIcons.strokeRoundedUserMultiple,
          iconColor,
        ),
      ),
      if (kDebugMode)
        EntePopupMenuOption(
          value: ClusterPopupAction.breakupClusterDebug,
          label: "Debug mixed grouping",
          leadingWidget: galleryAppBarMenuIcon(
            HugeIcons.strokeRoundedAiBrain01,
            iconColor,
          ),
        ),
    ];

    actions.add(
      galleryAppBarPopupMenuAction<ClusterPopupAction>(
        tooltip: AppLocalizations.of(context).more,
        icon: const HugeIcon(icon: HugeIcons.strokeRoundedMoreVertical),
        optionsBuilder: () => items,
        onSelected: (ClusterPopupAction value) async {
          if (value == ClusterPopupAction.breakupCluster) {
            await _breakUpCluster(context);
          } else if (value == ClusterPopupAction.ignore) {
            await _onIgnoredClusterClicked(context);
          } else if (value == ClusterPopupAction.breakupClusterDebug) {
            await _breakUpClusterDebug(context);
          }
        },
      ),
    );

    return actions;
  }

  Future<void> _onIgnoredClusterClicked(BuildContext context) async {
    final result = await showChoiceDialog(
      context,
      title: AppLocalizations.of(context).areYouSureYouWantToIgnoreThisPerson,
      body: AppLocalizations.of(context).thePersonGroupsWillNotBeDisplayed,
      firstButtonLabel: AppLocalizations.of(context).confirm,
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
      title: AppLocalizations.of(context).doesGroupContainMultiplePeople,
      body: AppLocalizations.of(context).automaticallyAnalyzeAndSplitGrouping,
      firstButtonLabel: AppLocalizations.of(context).confirm,
      firstButtonOnTap: () async {
        try {
          final breakupResult = await ClusterFeedbackService.instance
              .breakUpCluster(widget.clusterID);
          final Map<String, List<String>> newClusterIDToFaceIDs =
              breakupResult.newClusterIdToFaceIds;
          final Map<String, String> newFaceIdToClusterID =
              breakupResult.newFaceIdToCluster;

          // Update to delete the old clusters and save the new clusters
          await mlDataDB.deleteClusterSummary(widget.clusterID);
          await MLDataDB.instance.clusterSummaryUpdate(
            breakupResult.newClusterSummaries,
          );
          await mlDataDB.updateFaceIdToClusterId(newFaceIdToClusterID);

          // Find the biggest cluster
          biggestClusterID = '';
          int biggestClusterSize = 0;
          for (final MapEntry<String, List<String>> clusterToFaces
              in newClusterIDToFaceIDs.entries) {
            if (clusterToFaces.value.length > biggestClusterSize) {
              biggestClusterSize = clusterToFaces.value.length;
              biggestClusterID = clusterToFaces.key;
            }
          }
          // Get the files for the biggest new cluster
          final biggestClusterFileIDs = newClusterIDToFaceIDs[biggestClusterID]!
              .map((e) => getFileIdFromFaceId<int>(e))
              .toList();
          biggestClusterFiles = await FilesDB.instance
              .getFileIDToFileFromIDs(biggestClusterFileIDs)
              .then((mapping) => mapping.values.toList());
          // Sort the files to prevent issues with the order of the files in gallery
          biggestClusterFiles.sort(
            (a, b) => b.creationTime!.compareTo(a.creationTime!),
          );

          userConfirmed = true;
        } catch (e, s) {
          _logger.severe('Breakup cluster failed', e, s);
          // await showGenericErrorDialog(context: context, error: e);
        }
      },
    );
    if (userConfirmed) {
      Bus.instance.fire(PeopleChangedEvent());

      // Close the old cluster page
      if (!context.mounted) return;
      Navigator.of(context).pop();

      // Push the new cluster page
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
        builder: (context) => ClusterBreakupPage(
          newClusterIDToFiles,
          AppLocalizations.of(context).analysis,
        ),
      ),
    );
  }
}
