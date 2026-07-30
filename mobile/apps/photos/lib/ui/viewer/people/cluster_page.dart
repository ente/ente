import "dart:async";

import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:flutter/foundation.dart";
import "package:flutter/material.dart";
import "package:photos/core/configuration.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/events/app_mode_changed_event.dart";
import "package:photos/events/files_updated_event.dart";
import "package:photos/events/local_photos_updated_event.dart";
import "package:photos/events/people_changed_event.dart";
import "package:photos/generated/l10n.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/file_load_result.dart";
import "package:photos/models/gallery_type.dart";
import "package:photos/models/ml/face/person.dart";
import "package:photos/models/selected_files.dart";
import "package:photos/service_locator.dart" show isLocalGalleryMode;
import "package:photos/services/machine_learning/face_ml/feedback/cluster_feedback.dart";
import "package:photos/services/machine_learning/ml_result.dart";
import "package:photos/ui/components/banners/name_face_banner.dart";
import "package:photos/ui/notification/toast.dart";
import "package:photos/ui/viewer/actions/file_selection_overlay_bar.dart";
import "package:photos/ui/viewer/gallery/gallery.dart";
import "package:photos/ui/viewer/gallery/state/gallery_boundaries_provider.dart";
import "package:photos/ui/viewer/gallery/state/gallery_files_inherited_widget.dart";
import "package:photos/ui/viewer/gallery/state/selection_state.dart";
import "package:photos/ui/viewer/people/add_person_action_sheet.dart";
import "package:photos/ui/viewer/people/cluster_app_bar.dart";
import "package:photos/ui/viewer/people/people_page.dart";
import "package:photos/ui/viewer/people/person_face_widget.dart";
import "package:photos/ui/viewer/people/save_person_banner.dart";
import "package:photos/ui/viewer/search/result/search_result_page.dart";

class ClusterPage extends StatefulWidget {
  final List<EnteFile> searchResult;
  final bool enableGrouping;
  final String tagPrefix;
  final String clusterID;
  final PersonEntity? personID;
  final String appendTitle;
  final bool showNamingBanner;

  static const GalleryType appBarType = GalleryType.cluster;
  static const GalleryType overlayType = GalleryType.cluster;

  const ClusterPage(
    this.searchResult, {
    this.enableGrouping = true,
    this.tagPrefix = "",
    required this.clusterID,
    this.personID,
    this.appendTitle = "",
    this.showNamingBanner = true,
    super.key,
  });

  @override
  State<ClusterPage> createState() => _ClusterPageState();
}

enum ClusterPageResult { ignoredPerson }

class _ClusterPageState extends State<ClusterPage> {
  final _selectedFiles = SelectedFiles();
  late final List<EnteFile> files;
  late final StreamSubscription<LocalPhotosUpdatedEvent> _filesUpdatedEvent;
  late final StreamSubscription<PeopleChangedEvent> _peopleChangedEvent;
  late final StreamSubscription<AppModeChangedEvent> _appModeChangedEvent;
  bool get _localGalleryUiMode =>
      isLocalGalleryMode && !Configuration.instance.hasConfiguredAccount();

  @override
  void initState() {
    super.initState();
    ClusterFeedbackService.setLastViewedClusterID(widget.clusterID);
    files = List<EnteFile>.from(widget.searchResult)
      ..sort((a, b) => (b.creationTime ?? 0).compareTo(a.creationTime ?? 0));
    _filesUpdatedEvent = Bus.instance.on<LocalPhotosUpdatedEvent>().listen((
      event,
    ) {
      if (event.type == EventType.deletedFromEverywhere ||
          event.type == EventType.deletedFromRemote ||
          event.type == EventType.hide) {
        for (var updatedFile in event.updatedFiles) {
          files.remove(updatedFile);
        }
        setState(() {});
      }
    });
    _peopleChangedEvent = Bus.instance.on<PeopleChangedEvent>().listen((event) {
      if (event.source == widget.clusterID.toString()) {
        if (event.type == PeopleEventType.removedFilesFromCluster) {
          for (var updatedFile in event.relevantFiles!) {
            files.remove(updatedFile);
          }
          setState(() {});
        }
        if (event.type == PeopleEventType.removedFaceFromCluster) {
          for (final String removedFaceID in event.relevantFaceIDs!) {
            final int fileID = getFileIdFromFaceId<int>(removedFaceID);
            files.removeWhere((file) => file.uploadedFileID == fileID);
          }
          setState(() {});
        }
      }
    });
    _appModeChangedEvent = Bus.instance.on<AppModeChangedEvent>().listen((_) {
      if (mounted) {
        setState(() {});
      }
    });
    kDebugMode
        ? ClusterFeedbackService.instance.debugLogClusterBlurValues(
            widget.clusterID,
            clusterSize: files.length,
          )
        : null;
  }

  @override
  void dispose() {
    _filesUpdatedEvent.cancel();
    _peopleChangedEvent.cancel();
    _appModeChangedEvent.cancel();
    if (ClusterFeedbackService.lastViewedClusterID == widget.clusterID) {
      ClusterFeedbackService.resetLastViewedClusterID();
    }
    super.dispose();
  }

  Future<void> _handleSavePerson() async {
    if (_localGalleryUiMode) {
      return;
    }
    if (widget.personID == null) {
      final result = await showAssignPersonAction(
        context,
        clusterID: widget.clusterID,
        file: files.isEmpty ? null : files.first,
      );
      if (!mounted) {
        return;
      }
      if (result != null) {
        Navigator.pop(context);
        final person = result is (PersonEntity, EnteFile) ? result.$1 : result;
        routeToPage(
          context,
          PeoplePage(person: person, searchResult: null),
        ).ignore();
      }
    } else {
      showShortToast(context, "No personID or clusterID");
    }
  }

  @override
  Widget build(BuildContext context) {
    final appBar = ClusterAppBar.sliverConfig(
      SearchResultPage.appBarType,
      "${files.length} memories${widget.appendTitle}",
      _selectedFiles,
      widget.clusterID,
    );
    final gallery = Gallery(
      appBar: appBar,
      asyncLoader: (creationStartTime, creationEndTime, {limit, asc}) {
        final result = files
            .where(
              (file) =>
                  file.creationTime! >= creationStartTime &&
                  file.creationTime! <= creationEndTime,
            )
            .toList();
        return Future.value(
          FileLoadResult(result, result.length < files.length),
        );
      },
      reloadEvent: Bus.instance.on<LocalPhotosUpdatedEvent>(),
      forceReloadEvents: [Bus.instance.on<PeopleChangedEvent>()],
      removalEventTypes: const {
        EventType.deletedFromRemote,
        EventType.deletedFromEverywhere,
        EventType.hide,
        EventType.peopleClusterChanged,
      },
      tagPrefix: widget.tagPrefix + widget.tagPrefix,
      selectedFiles: _selectedFiles,
      enableFileGrouping: widget.enableGrouping,
      initialFiles: files,
      header:
          (_localGalleryUiMode || widget.showNamingBanner) && files.isNotEmpty
          ? _localGalleryUiMode
                ? const NameFaceBanner()
                : SavePersonBanner(
                    faceWidget: PersonFaceWidget(clusterID: widget.clusterID),
                    text: AppLocalizations.of(context).savePerson,
                    subText: AppLocalizations.of(context).findThemQuickly,
                    onTap: _handleSavePerson,
                  )
          : null,
    );
    return GalleryBoundariesProvider(
      child: GalleryFilesState(
        child: Scaffold(
          body: SelectionState(
            selectedFiles: _selectedFiles,
            child: Stack(
              alignment: Alignment.bottomCenter,
              children: [
                gallery,
                FileSelectionOverlayBar(
                  ClusterPage.overlayType,
                  _selectedFiles,
                  clusterID: widget.clusterID,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
