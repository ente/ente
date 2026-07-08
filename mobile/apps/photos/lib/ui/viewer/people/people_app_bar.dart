import 'dart:async';

import "package:ente_components/ente_components.dart";
import "package:ente_pure_utils/ente_pure_utils.dart";
import 'package:flutter/material.dart';
import "package:hugeicons/hugeicons.dart";
import 'package:logging/logging.dart';
import 'package:photos/core/configuration.dart';
import 'package:photos/core/event_bus.dart';
import "package:photos/events/people_changed_event.dart";
import 'package:photos/events/subscription_purchased_event.dart';
import "package:photos/generated/l10n.dart";
import "package:photos/l10n/l10n.dart";
import 'package:photos/models/gallery_type.dart';
import "package:photos/models/ml/face/person.dart";
import 'package:photos/models/selected_files.dart';
import 'package:photos/services/collections_service.dart';
import "package:photos/services/machine_learning/face_ml/person/person_service.dart";
import "package:photos/theme/ente_theme.dart";
import 'package:photos/ui/actions/collection/collection_sharing_actions.dart';
import "package:photos/ui/components/buttons/button_widget.dart";
import "package:photos/ui/notification/toast.dart";
import "package:photos/ui/viewer/gallery/gallery_app_bar_actions.dart";
import "package:photos/ui/viewer/gallery/gallery_app_bar_config.dart";
import "package:photos/ui/viewer/gallery/hooks/pick_person_avatar.dart";
import "package:photos/ui/viewer/gallery/state/inherited_search_filter_data.dart";
import "package:photos/ui/viewer/hierarchicial_search/app_bar_filter_chips.dart";
import "package:photos/ui/viewer/people/person_cluster_suggestion.dart";
import "package:photos/ui/viewer/people/person_selection_action_widgets.dart";
import "package:photos/ui/viewer/people/save_or_edit_person.dart";
import "package:photos/utils/dialog_util.dart";

const kShowUnnamedIgnoredPersonEventSource =
    "_AppBarWidgetState._showPersonUnnamedDelete";

class PeopleAppBar extends StatefulWidget {
  static const double _sliverExpandedHeight = 92.0;

  static GalleryAppBarConfig sliverConfig(
    GalleryType type,
    String? title,
    SelectedFiles selectedFiles,
    PersonEntity person, {
    bool memoryLaneReady = false,
    Future<void> Function()? onMemoryLaneTap,
  }) {
    return GalleryAppBarConfig(
      sliverBuilder: (_) => PeopleAppBar._(
        type,
        title,
        selectedFiles,
        person,
        memoryLaneReady: memoryLaneReady,
        onMemoryLaneTap: onMemoryLaneTap,
      ),
      geometryBuilder: _resolveSliverGeometry,
    );
  }

  static HeaderAppBarGeometry _resolveSliverGeometry(BuildContext context) {
    final inheritedSearchFilterData = InheritedSearchFilterData.maybeOf(
      context,
    );
    final isHierarchicalSearchable =
        inheritedSearchFilterData?.isHierarchicalSearchable ?? false;
    final bottomHeight = isHierarchicalSearchable
        ? AppBarFilterChips.preferredHeight(context)
        : 0.0;
    return SliverAppBarComponent.resolveGeometry(
      context,
      expandedHeight: _sliverExpandedHeight,
      collapsedHeight: kToolbarHeight,
      bottomHeight: bottomHeight,
    );
  }

  final GalleryType type;
  final String? title;
  final SelectedFiles selectedFiles;
  final PersonEntity person;
  final bool memoryLaneReady;
  final Future<void> Function()? onMemoryLaneTap;

  bool get isIgnored => person.data.isIgnored;

  const PeopleAppBar._(
    this.type,
    this.title,
    this.selectedFiles,
    this.person, {
    this.memoryLaneReady = false,
    this.onMemoryLaneTap,
  });

  @override
  State<PeopleAppBar> createState() => _AppBarWidgetState();
}

enum PeoplePopupAction {
  rename,
  setCover,
  pinPerson,
  hideFromMemories,
  ignore,
  removeLabel,
  reviewSuggestions,
  unignore,
  reassignMe,
  memoryLane,
}

class _AppBarWidgetState extends State<PeopleAppBar> {
  final _logger = Logger("_AppBarWidgetState");
  late StreamSubscription _userAuthEventSubscription;
  late Function() _selectedFilesListener;
  String? _appBarTitle;
  late CollectionActions collectionActions;
  final GlobalKey shareButtonKey = GlobalKey();
  bool isQuickLink = false;
  late GalleryType galleryType;
  late PersonEntity person;
  late StreamSubscription<PeopleChangedEvent> _peopleChangedEventSubscription;

  String? _resolveAppBarTitle({
    required PersonEntity sourcePerson,
    required String? title,
  }) {
    if (sourcePerson.data.email == Configuration.instance.getEmail()) {
      if (title == null) {
        return context.l10n.me;
      }
      return context.l10n.accountOwnerPersonAppbarTitle(title: title);
    }
    return title;
  }

  @override
  void initState() {
    super.initState();
    person = widget.person;
    galleryType = widget.type;
    collectionActions = CollectionActions(CollectionsService.instance);
    _selectedFilesListener = () {
      setState(() {});
    };

    widget.selectedFiles.addListener(_selectedFilesListener);
    _userAuthEventSubscription = Bus.instance
        .on<SubscriptionPurchasedEvent>()
        .listen((event) {
          setState(() {});
        });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      setState(() {
        _appBarTitle = _resolveAppBarTitle(
          sourcePerson: person,
          title: widget.title,
        );

        _peopleChangedEventSubscription = Bus.instance
            .on<PeopleChangedEvent>()
            .listen((event) {
              if (event.person != null &&
                  event.type == PeopleEventType.saveOrEditPerson &&
                  widget.person.remoteID == event.person!.remoteID &&
                  (event.source == "linkEmailToPerson" ||
                      event.source == "reassignMe")) {
                person = event.person!;

                _appBarTitle = _resolveAppBarTitle(
                  sourcePerson: person,
                  title: person.data.name,
                );
                setState(() {});
              }
            });
      });
    });
  }

  @override
  void didUpdateWidget(covariant PeopleAppBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.title != widget.title ||
        oldWidget.person.remoteID != widget.person.remoteID ||
        oldWidget.person.data.name != widget.person.data.name ||
        oldWidget.person.data.email != widget.person.data.email) {
      person = widget.person;
      _appBarTitle = _resolveAppBarTitle(
        sourcePerson: person,
        title: widget.title,
      );
    }
  }

  @override
  void dispose() {
    _userAuthEventSubscription.cancel();
    widget.selectedFiles.removeListener(_selectedFilesListener);
    _peopleChangedEventSubscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final inheritedSearchFilterData = InheritedSearchFilterData.maybeOf(
      context,
    );
    final isHierarchicalSearchable =
        inheritedSearchFilterData?.isHierarchicalSearchable ?? false;

    if (!isHierarchicalSearchable) {
      return _buildSliverAppBar(context, actions: _getDefaultActions(context));
    }

    return ValueListenableBuilder(
      valueListenable: inheritedSearchFilterData!
          .searchFilterDataProvider!
          .isSearchingNotifier,
      child: PreferredSize(
        preferredSize: Size.fromHeight(
          AppBarFilterChips.preferredHeight(context),
        ),
        child: const AppBarFilterChips(),
      ),
      builder: (context, isSearching, child) {
        return _buildSliverAppBar(
          context,
          actions: isSearching ? const [] : _getDefaultActions(context),
          bottom: child as PreferredSizeWidget,
        );
      },
    );
  }

  Widget _buildSliverAppBar(
    BuildContext context, {
    required List<Widget> actions,
    PreferredSizeWidget? bottom,
  }) {
    return SliverAppBarComponent(
      title: _appBarTitle ?? "",
      actions: actions,
      bottom: bottom,
      expandedHeight: PeopleAppBar._sliverExpandedHeight,
      collapsedHeight: kToolbarHeight,
      backgroundColor: getEnteColorScheme(context).backgroundColour,
    );
  }

  Future<dynamic> _editPerson(BuildContext context) async {
    final clusterID = person.data.assigned.isEmpty
        ? null
        : person.data.assigned.first.id;
    final result = await routeToPage(
      context,
      SaveOrEditPerson(clusterID, person: person, isEditing: true),
    );
    if (result is PersonEntity) {
      _appBarTitle = result.data.name;
      person = result;
      setState(() {});
    }
  }

  List<Widget> _getDefaultActions(BuildContext context) {
    final iconColor = getEnteColorScheme(context).contentLight;
    final bool isIgnored = person.data.isIgnored;
    final bool isPinned = person.data.isPinned;
    final bool hideFromMemories = person.data.hideFromMemories;
    final bool hasAssignedCluster = person.data.assigned.isNotEmpty;
    final List<Widget> actions = <Widget>[];
    // If the user has selected files, don't show any actions
    if (widget.selectedFiles.files.isNotEmpty ||
        !Configuration.instance.hasConfiguredAccount()) {
      return actions;
    }

    final List<EntePopupMenuOption<PeoplePopupAction>> items = [];
    final bool showTimelineAction =
        widget.memoryLaneReady && widget.onMemoryLaneTap != null;
    if (showTimelineAction) {
      items.add(
        EntePopupMenuOption(
          value: PeoplePopupAction.memoryLane,
          label: context.l10n.facesTimelineAppBarTitle,
          leadingWidget: galleryAppBarMenuIcon(
            HugeIcons.strokeRoundedSparkles,
            iconColor,
          ),
        ),
      );
    }

    if (!isIgnored) {
      items.addAll([
        EntePopupMenuOption(
          value: PeoplePopupAction.rename,
          label: AppLocalizations.of(context).edit,
          leadingWidget: galleryAppBarMenuIcon(
            HugeIcons.strokeRoundedPencilEdit01,
            iconColor,
          ),
        ),
        if (hasAssignedCluster)
          EntePopupMenuOption(
            value: PeoplePopupAction.reviewSuggestions,
            label: AppLocalizations.of(context).review,
            leadingWidget: galleryAppBarMenuIcon(
              HugeIcons.strokeRoundedSearch01,
              iconColor,
            ),
          ),
        if (hasAssignedCluster)
          EntePopupMenuOption(
            value: PeoplePopupAction.setCover,
            label: AppLocalizations.of(context).setCover,
            leadingWidget: galleryAppBarMenuIcon(
              HugeIcons.strokeRoundedImage01,
              iconColor,
            ),
          ),
        EntePopupMenuOption(
          value: PeoplePopupAction.pinPerson,
          label: isPinned ? context.l10n.unpinPerson : context.l10n.pinPerson,
          leadingWidget: galleryAppBarMenuIcon(
            isPinned
                ? HugeIcons.strokeRoundedPinOff
                : HugeIcons.strokeRoundedPin,
            iconColor,
          ),
        ),
        EntePopupMenuOption(
          value: PeoplePopupAction.hideFromMemories,
          label: hideFromMemories
              ? context.l10n.showInMemories
              : context.l10n.hideFromMemories,
          leadingWidget: galleryAppBarMenuIcon(
            hideFromMemories
                ? HugeIcons.strokeRoundedView
                : HugeIcons.strokeRoundedViewOffSlash,
            iconColor,
          ),
        ),
        if (person.data.email != null &&
            (person.data.email == Configuration.instance.getEmail()))
          EntePopupMenuOption(
            value: PeoplePopupAction.reassignMe,
            label: context.l10n.reassignMe,
            leadingWidget: galleryAppBarMenuIcon(
              HugeIcons.strokeRoundedUser,
              iconColor,
            ),
          ),
        EntePopupMenuOption(
          value: PeoplePopupAction.ignore,
          label: AppLocalizations.of(context).ignore,
          leadingWidget: galleryAppBarMenuIcon(
            HugeIcons.strokeRoundedUserBlock01,
            iconColor,
          ),
        ),
        EntePopupMenuOption(
          value: PeoplePopupAction.removeLabel,
          label: AppLocalizations.of(context).remove,
          leadingWidget: galleryAppBarMenuIcon(
            HugeIcons.strokeRoundedDelete01,
            iconColor,
          ),
        ),
      ]);
    } else {
      items.addAll([
        EntePopupMenuOption(
          value: PeoplePopupAction.rename,
          label: AppLocalizations.of(context).edit,
          leadingWidget: galleryAppBarMenuIcon(
            HugeIcons.strokeRoundedPencilEdit01,
            iconColor,
          ),
        ),
        if (hasAssignedCluster)
          EntePopupMenuOption(
            value: PeoplePopupAction.reviewSuggestions,
            label: AppLocalizations.of(context).review,
            leadingWidget: galleryAppBarMenuIcon(
              HugeIcons.strokeRoundedSearch01,
              iconColor,
            ),
          ),
        EntePopupMenuOption(
          value: PeoplePopupAction.unignore,
          label: AppLocalizations.of(context).showPerson,
          leadingWidget: galleryAppBarMenuIcon(
            HugeIcons.strokeRoundedView,
            iconColor,
          ),
        ),
      ]);
    }

    actions.add(
      galleryAppBarPopupMenuAction<PeoplePopupAction>(
        tooltip: AppLocalizations.of(context).more,
        icon: const HugeIcon(icon: HugeIcons.strokeRoundedMoreVertical),
        optionsBuilder: () => items,
        onSelected: (PeoplePopupAction value) async {
          if (value == PeoplePopupAction.reviewSuggestions) {
            unawaited(
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => PersonReviewClusterSuggestion(person),
                ),
              ),
            );
          } else if (value == PeoplePopupAction.memoryLane) {
            final callback = widget.onMemoryLaneTap;
            if (callback != null) {
              unawaited(callback());
            }
          } else if (value == PeoplePopupAction.rename) {
            await _editPerson(context);
          } else if (value == PeoplePopupAction.setCover) {
            await setCoverPhoto(context);
          } else if (value == PeoplePopupAction.pinPerson) {
            await _togglePinState();
          } else if (value == PeoplePopupAction.hideFromMemories) {
            await _toggleHideFromMemories();
          } else if (value == PeoplePopupAction.ignore) {
            await _ignorePerson(context);
          } else if (value == PeoplePopupAction.unignore) {
            await _showPerson(context);
          } else if (value == PeoplePopupAction.removeLabel) {
            await _resetPerson(context);
          } else if (value == PeoplePopupAction.reassignMe) {
            await _reassignMe(context);
          }
        },
      ),
    );

    return actions;
  }

  Future<void> _togglePinState() async {
    final shouldPin = !person.data.isPinned;
    try {
      final updatedPerson = await PersonService.instance.updateAttributes(
        person.remoteID,
        isPinned: shouldPin,
      );
      setState(() {
        person = updatedPerson;
      });
      Bus.instance.fire(
        PeopleChangedEvent(
          type: PeopleEventType.saveOrEditPerson,
          source: "_AppBarWidgetState._togglePinState",
          person: updatedPerson,
        ),
      );
    } catch (e, s) {
      _logger.severe('Failed to update pin state', e, s);
    }
  }

  Future<void> _toggleHideFromMemories() async {
    final shouldHideFromMemories = !person.data.hideFromMemories;
    try {
      final updatedPerson = await PersonService.instance.updateAttributes(
        person.remoteID,
        hideFromMemories: shouldHideFromMemories,
      );
      setState(() {
        person = updatedPerson;
      });
      Bus.instance.fire(
        PeopleChangedEvent(
          type: PeopleEventType.saveOrEditPerson,
          source: "_AppBarWidgetState._toggleHideFromMemories",
          person: updatedPerson,
        ),
      );
    } catch (e, s) {
      _logger.severe('Failed to update hide from memories state', e, s);
    }
  }

  Future<void> _resetPerson(BuildContext context) async {
    await showChoiceDialog(
      context,
      title: AppLocalizations.of(context).areYouSureYouWantToResetThisPerson,
      body: AppLocalizations.of(context).allPersonGroupingWillReset,
      firstButtonLabel: AppLocalizations.of(context).yesResetPerson,
      firstButtonOnTap: () async {
        try {
          await PersonService.instance.deletePerson(person.remoteID);
          Navigator.of(context).pop();
        } catch (e, s) {
          _logger.severe('Resetting person failed', e, s);
        }
      },
    );
  }

  bool _isLegacyIgnoredName(String name) {
    final normalizedName = name.trim().toLowerCase();
    return normalizedName.isEmpty ||
        normalizedName == "(ignored)" ||
        normalizedName == "(hidden)";
  }

  Future<void> _ignorePerson(BuildContext context) async {
    final result = await showChoiceDialog(
      context,
      title: AppLocalizations.of(context).areYouSureYouWantToIgnoreThisPerson,
      body: AppLocalizations.of(context).thePersonWillNotBeDisplayed,
      firstButtonLabel: AppLocalizations.of(context).yesIgnore,
      firstButtonOnTap: () async {
        try {
          final updatedPerson = await PersonService.instance.updateAttributes(
            person.remoteID,
            isHidden: true,
          );
          setState(() {
            person = updatedPerson;
          });
          Bus.instance.fire(
            PeopleChangedEvent(
              type: PeopleEventType.saveOrEditPerson,
              source: "_AppBarWidgetState._ignorePerson",
              person: updatedPerson,
            ),
          );
        } catch (e, s) {
          _logger.severe('Ignoring/showing person failed', e, s);
          rethrow;
        }
      },
    );
    if (!mounted || result?.action != ButtonAction.error) {
      return;
    }
    showShortToast(
      context,
      AppLocalizations.of(context).somethingWentWrongPleaseTryAgain,
    );
  }

  Future<void> _showPerson(BuildContext context) async {
    final isUnnamedIgnoredPerson = _isLegacyIgnoredName(person.data.name);
    var shouldCloseDetailPage = false;
    final result = await showChoiceDialog(
      context,
      title: AppLocalizations.of(
        context,
      ).areYouSureYouWantToShowThisPersonInPeopleSectionAgain,
      firstButtonLabel: AppLocalizations.of(context).yesShowPerson,
      isDismissible: false,
      firstButtonOnTap: () async {
        try {
          if (isUnnamedIgnoredPerson) {
            await PersonService.instance.deletePerson(person.remoteID);
            Bus.instance.fire(
              PeopleChangedEvent(
                source: kShowUnnamedIgnoredPersonEventSource,
                person: person,
              ),
            );
            shouldCloseDetailPage = true;
          } else {
            final updatedPerson = await PersonService.instance.updateAttributes(
              person.remoteID,
              isHidden: false,
            );
            setState(() {
              person = updatedPerson;
              _appBarTitle = _resolveAppBarTitle(
                sourcePerson: person,
                title: person.data.name,
              );
            });
            Bus.instance.fire(
              PeopleChangedEvent(
                type: PeopleEventType.saveOrEditPerson,
                source: "_AppBarWidgetState._showPerson",
                person: updatedPerson,
              ),
            );
          }
        } catch (e, s) {
          _logger.severe('Unignoring/showing person failed', e, s);
        }
      },
    );
    if (!mounted ||
        result?.action != ButtonAction.first ||
        !shouldCloseDetailPage) {
      return;
    }
    await Navigator.of(context).maybePop();
  }

  Future<void> setCoverPhoto(BuildContext context) async {
    final result = await showPersonAvatarPhotoSheet(context, person);
    if (result != null) {
      _logger.info('Person avatar updated');
      setState(() {
        person = result;
      });
      Bus.instance.fire(
        PeopleChangedEvent(
          type: PeopleEventType.saveOrEditPerson,
          source: "_PeopleAppBarState.setCoverPhoto",
          person: result,
        ),
      );
    }
  }

  Future<void> _reassignMe(BuildContext context) async {
    await routeToPage(
      context,
      ReassignMeSelectionPage(currentMeId: widget.person.remoteID),
    );
  }
}
