import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:flutter/material.dart";
import "package:hugeicons/hugeicons.dart";
import "package:logging/logging.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/events/people_changed_event.dart";
import "package:photos/generated/l10n.dart";
import "package:photos/l10n/l10n.dart";
import "package:photos/models/ml/face/person.dart";
import "package:photos/models/search/search_constants.dart";
import "package:photos/models/selected_people.dart";
import "package:photos/services/machine_learning/face_ml/face_filtering/face_filtering_constants.dart";
import "package:photos/services/machine_learning/face_ml/feedback/cluster_feedback.dart";
import "package:photos/services/machine_learning/face_ml/person/person_service.dart";
import "package:photos/services/search_service.dart";
import "package:photos/theme/ente_theme.dart";
import "package:photos/ui/collections/collection_action_sheet.dart";
import "package:photos/ui/components/bottom_action_bar/selection_action_button_widget.dart";
import "package:photos/ui/components/buttons/button_widget.dart";
import "package:photos/ui/viewer/people/merge_clusters_to_person_sheet.dart";
import "package:photos/ui/viewer/people/person_cluster_suggestion.dart";
import "package:photos/ui/viewer/people/save_or_edit_person.dart";
import "package:photos/utils/dialog_util.dart";

class PeopleSelectionActionWidget extends StatefulWidget {
  final SelectedPeople selectedPeople;

  const PeopleSelectionActionWidget(this.selectedPeople, {super.key});

  @override
  State<PeopleSelectionActionWidget> createState() =>
      _PeopleSelectionActionWidgetState();
}

class _PeopleSelectionActionWidgetState
    extends State<PeopleSelectionActionWidget> {
  late Future<Map<String, PersonEntity>> personEntitiesMapFuture;
  final _logger = Logger("PeopleSelectionActionWidget");

  bool _isUnnamedIgnoredPerson(PersonEntity person) {
    final normalizedName = person.data.name.trim().toLowerCase();
    return normalizedName.isEmpty ||
        normalizedName == "(ignored)" ||
        normalizedName == "(hidden)";
  }

  @override
  void initState() {
    super.initState();
    widget.selectedPeople.addListener(_selectionChangedListener);
    personEntitiesMapFuture = PersonService.instance.getPersonsMap();
  }

  @override
  void dispose() {
    widget.selectedPeople.removeListener(_selectionChangedListener);
    super.dispose();
  }

  List<String> _getSelectedPersonIds(Map<String, PersonEntity> personMap) {
    return widget.selectedPeople.personIds
        .where((id) => !id.startsWith('cluster_') && personMap.containsKey(id))
        .toList();
  }

  List<String> _getSelectedClusterIds() {
    return widget.selectedPeople.personIds
        .where((id) => id.startsWith('cluster_'))
        .toList();
  }

  List<String> _getNamedSelectedPersonIds(
    Iterable<String> personIds,
    Map<String, PersonEntity> personMap,
  ) {
    return personIds
        .where((id) => (personMap[id]?.data.name ?? "").isNotEmpty)
        .toList();
  }

  bool _hasAssignedCluster(
    String personID,
    Map<String, PersonEntity> personMap,
  ) {
    return personMap[personID]?.data.assigned.isNotEmpty ?? false;
  }

  void _selectionChangedListener() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.selectedPeople.personIds.isEmpty) {
      return const SizedBox.shrink();
    }

    return FutureBuilder<Map<String, PersonEntity>>(
      future: personEntitiesMapFuture,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const SizedBox.shrink();
        }
        final personMap = snapshot.data!;
        final List<SelectionActionButton> items = [];
        final selectedPersonIds = _getSelectedPersonIds(personMap);
        final selectedClusterIds = _getSelectedClusterIds();
        final onlyOnePerson =
            selectedPersonIds.length == 1 && selectedClusterIds.isEmpty;
        final onlyPersonSelected =
            selectedPersonIds.isNotEmpty && selectedClusterIds.isEmpty;
        final onlySelectedPersonHasAssignedCluster =
            onlyOnePerson &&
            _hasAssignedCluster(selectedPersonIds.first, personMap);
        final ignoredSelectedPersonIds = selectedPersonIds
            .where((id) => personMap[id]?.data.isIgnored ?? false)
            .toList();
        final onlyIgnoredPersonsSelected =
            ignoredSelectedPersonIds.isNotEmpty &&
            selectedClusterIds.isEmpty &&
            ignoredSelectedPersonIds.length == selectedPersonIds.length;
        final bool namedPersonsSelected =
            selectedPersonIds.isNotEmpty &&
            selectedPersonIds.every(
              (id) => (personMap[id]?.data.name ?? "").isNotEmpty,
            );
        final bool showEditAction = onlyOnePerson;
        final bool showReviewAction = onlySelectedPersonHasAssignedCluster;
        final bool showMergeAction = onlyIgnoredPersonsSelected
            ? false
            : selectedClusterIds.isNotEmpty;
        final bool showResetAction = onlyIgnoredPersonsSelected
            ? false
            : onlyOnePerson;
        final bool showShowPersonAction = onlyIgnoredPersonsSelected;
        final bool showAutoAddAction = onlyIgnoredPersonsSelected
            ? false
            : onlyPersonSelected;
        final bool showPinAction = onlyIgnoredPersonsSelected
            ? false
            : onlyPersonSelected &&
                  namedPersonsSelected &&
                  selectedPersonIds.every(
                    (id) => !(personMap[id]?.data.isPinned ?? false),
                  );
        final bool showUnpinAction = onlyIgnoredPersonsSelected
            ? false
            : onlyPersonSelected &&
                  namedPersonsSelected &&
                  selectedPersonIds.every(
                    (id) => personMap[id]?.data.isPinned ?? false,
                  );
        final bool showHideFromMemoriesAction = onlyIgnoredPersonsSelected
            ? false
            : onlyPersonSelected &&
                  namedPersonsSelected &&
                  selectedPersonIds.every(
                    (id) => !(personMap[id]?.data.hideFromMemories ?? false),
                  );
        final bool showShowInMemoriesAction = onlyIgnoredPersonsSelected
            ? false
            : onlyPersonSelected &&
                  namedPersonsSelected &&
                  selectedPersonIds.every(
                    (id) => personMap[id]?.data.hideFromMemories ?? false,
                  );
        final bool hasNonIgnoredSelectedPerson = selectedPersonIds.any(
          (id) => !(personMap[id]?.data.isIgnored ?? true),
        );
        final bool showIgnoreAction = onlyIgnoredPersonsSelected
            ? false
            : selectedClusterIds.isNotEmpty || hasNonIgnoredSelectedPerson;
        final bool hasVisibleAction =
            showEditAction ||
            showReviewAction ||
            showIgnoreAction ||
            showMergeAction ||
            showResetAction ||
            showShowPersonAction ||
            showPinAction ||
            showUnpinAction ||
            showHideFromMemoriesAction ||
            showShowInMemoriesAction ||
            showAutoAddAction;

        if (!hasVisibleAction) {
          return const SizedBox.shrink();
        }

        items.add(
          SelectionActionButton(
            labelText: AppLocalizations.of(context).edit,
            hugeIcon: HugeIcons.strokeRoundedPencilEdit01,
            onTap: _onEditPerson,
            shouldShow: showEditAction,
          ),
        );
        items.add(
          SelectionActionButton(
            labelText: AppLocalizations.of(context).review,
            hugeIcon: HugeIcons.strokeRoundedSearch01,
            onTap: _onReviewSuggestion,
            shouldShow: showReviewAction,
          ),
        );
        items.add(
          SelectionActionButton(
            labelText: AppLocalizations.of(context).ignore,
            hugeIcon: HugeIcons.strokeRoundedImageNotFound01,
            onTap: _onIgnore,
            shouldShow: showIgnoreAction,
          ),
        );
        items.add(
          SelectionActionButton(
            labelText: AppLocalizations.of(context).merge,
            hugeIcon: HugeIcons.strokeRoundedGitMerge,
            onTap: _onMerge,
            shouldShow: showMergeAction,
          ),
        );
        items.add(
          SelectionActionButton(
            labelText: AppLocalizations.of(context).reset,
            hugeIcon: HugeIcons.strokeRoundedRemove01,
            onTap: _onResetPerson,
            shouldShow: showResetAction,
          ),
        );
        items.add(
          SelectionActionButton(
            labelText: AppLocalizations.of(context).showPerson,
            hugeIcon: HugeIcons.strokeRoundedView,
            onTap: _onShowPerson,
            shouldShow: showShowPersonAction,
          ),
        );
        items.add(
          SelectionActionButton(
            labelText: AppLocalizations.of(context).pin,
            hugeIcon: HugeIcons.strokeRoundedPin,
            onTap: () => _updatePinState(true),
            shouldShow: showPinAction,
          ),
        );
        items.add(
          SelectionActionButton(
            labelText: AppLocalizations.of(context).unpin,
            hugeIcon: HugeIcons.strokeRoundedPinOff,
            onTap: () => _updatePinState(false),
            shouldShow: showUnpinAction,
          ),
        );
        items.add(
          SelectionActionButton(
            labelText: AppLocalizations.of(context).hideFromMemories,
            hugeIcon: HugeIcons.strokeRoundedViewOffSlash,
            onTap: () => _updateHideFromMemoriesState(true),
            shouldShow: showHideFromMemoriesAction,
          ),
        );
        items.add(
          SelectionActionButton(
            labelText: context.l10n.showInMemories,
            hugeIcon: HugeIcons.strokeRoundedView,
            onTap: () => _updateHideFromMemoriesState(false),
            shouldShow: showShowInMemoriesAction,
          ),
        );
        items.add(
          SelectionActionButton(
            labelText: AppLocalizations.of(context).autoAddToAlbum,
            iconWidget: Image.asset(
              "assets/auto-add-people.png",
              width: 22,
              height: 22,
              color: EnteTheme.isDark(context) ? Colors.white : Colors.black,
            ),
            onTap: _autoAddToAlbum,
            shouldShow: showAutoAddAction,
          ),
        );

        return MediaQuery(
          data: MediaQuery.of(context).removePadding(removeBottom: true),
          child: SafeArea(
            child: Scrollbar(
              radius: const Radius.circular(1),
              thickness: 2,
              thumbVisibility: true,
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(
                  decelerationRate: ScrollDecelerationRate.fast,
                ),
                scrollDirection: Axis.horizontal,
                child: Container(
                  padding: const EdgeInsets.only(bottom: 24),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(width: 4),
                      ...items,
                      const SizedBox(width: 4),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _onEditPerson() async {
    final personMap = await personEntitiesMapFuture;
    final selectedPersonIds = _getSelectedPersonIds(personMap);
    if (selectedPersonIds.length != 1) return;
    final personID = selectedPersonIds.first;
    final person = personMap[personID];
    if (person == null) return;
    final clusterID = person.data.assigned.isEmpty
        ? null
        : person.data.assigned.first.id;

    await routeToPage(
      context,
      SaveOrEditPerson(clusterID, person: person, isEditing: true),
    );
    widget.selectedPeople.clearAll();
  }

  Future<void> _onReviewSuggestion() async {
    final personMap = await personEntitiesMapFuture;
    final selectedPersonIds = _getSelectedPersonIds(personMap);
    if (selectedPersonIds.length != 1) return;
    final personID = selectedPersonIds.first;
    final person = personMap[personID];
    if (person == null) return;
    if (person.data.assigned.isEmpty) return;

    await routeToPage(context, PersonReviewClusterSuggestion(person));
    widget.selectedPeople.clearAll();
  }

  Future<void> _autoAddToAlbum() async {
    final personMap = await personEntitiesMapFuture;
    final selectedPersonIds = _getSelectedPersonIds(personMap);
    if (selectedPersonIds.isEmpty) return;
    showCollectionActionSheet(
      context,
      selectedPeople: selectedPersonIds,
      actionType: CollectionActionType.autoAddPeople,
    );
    widget.selectedPeople.clearAll();
  }

  Future<void> _updatePinState(bool shouldPin) async {
    try {
      final personMap = await personEntitiesMapFuture;
      final selectedPersonIds = _getSelectedPersonIds(personMap);
      if (selectedPersonIds.isEmpty) return;
      for (final personID in selectedPersonIds) {
        final person = personMap[personID];
        if (person == null || person.data.name.isEmpty) continue;
        if (person.data.isPinned == shouldPin) continue;
        final updatedPerson = person.copyWith(
          data: person.data.copyWith(isPinned: shouldPin),
        );
        await PersonService.instance.updatePerson(updatedPerson);
      }
      Bus.instance.fire(PeopleChangedEvent());
    } catch (e, s) {
      _logger.severe('Failed to update pin state', e, s);
    } finally {
      widget.selectedPeople.clearAll();
    }
  }

  Future<void> _updateHideFromMemoriesState(bool shouldHide) async {
    try {
      final personMap = await personEntitiesMapFuture;
      final selectedPersonIds = _getSelectedPersonIds(personMap);
      if (selectedPersonIds.isEmpty) return;
      for (final personID in selectedPersonIds) {
        final person = personMap[personID];
        if (person == null || person.data.name.isEmpty) continue;
        if (person.data.hideFromMemories == shouldHide) continue;
        await PersonService.instance.updateAttributes(
          person.remoteID,
          hideFromMemories: shouldHide,
        );
      }
      Bus.instance.fire(PeopleChangedEvent());
    } catch (e, s) {
      _logger.severe('Failed to update hide from memories state', e, s);
    } finally {
      widget.selectedPeople.clearAll();
    }
  }

  Future<void> _onResetPerson() async {
    final personMap = await personEntitiesMapFuture;
    final selectedPersonIds = _getSelectedPersonIds(personMap);
    if (selectedPersonIds.length != 1) return;
    final personID = selectedPersonIds.first;
    final person = personMap[personID];
    if (person == null) return;

    await showChoiceDialog(
      context,
      title: AppLocalizations.of(context).areYouSureYouWantToResetThisPerson,
      body: AppLocalizations.of(context).allPersonGroupingWillReset,
      firstButtonLabel: AppLocalizations.of(context).yesResetPerson,
      firstButtonOnTap: () async {
        try {
          await PersonService.instance.deletePerson(person.remoteID);
          widget.selectedPeople.clearAll();
        } on Exception catch (e, s) {
          _logger.severe('Failed to delete person', e, s);
        }
      },
    );
  }

  Future<void> _onIgnore() async {
    final personMap = await personEntitiesMapFuture;
    final selectedPersonIds = _getSelectedPersonIds(personMap);
    final selectedClusterIds = _getSelectedClusterIds();
    if (selectedPersonIds.isEmpty && selectedClusterIds.isEmpty) return;
    final multiple = (selectedPersonIds.length + selectedClusterIds.length) > 1;

    final result = await showChoiceDialog(
      context,
      title: multiple
          ? AppLocalizations.of(context).areYouSureYouWantToIgnoreThesePersons
          : AppLocalizations.of(context).areYouSureYouWantToIgnoreThisPerson,
      body: multiple
          ? AppLocalizations.of(context).thePersonGroupsWillNotBeDisplayed
          : AppLocalizations.of(context).thePersonWillNotBeDisplayed,
      firstButtonLabel: AppLocalizations.of(context).yesIgnore,
    );
    if (!mounted || result?.action != ButtonAction.first) {
      return;
    }

    try {
      await _ignoreSelectedItems(
        personMap: personMap,
        selectedPersonIds: selectedPersonIds,
        selectedClusterIds: selectedClusterIds,
      );
    } catch (e, s) {
      _logger.severe('Ignoring a cluster failed', e, s);
    }
  }

  Future<void> _ignoreSelectedItems({
    required Map<String, PersonEntity> personMap,
    required List<String> selectedPersonIds,
    required List<String> selectedClusterIds,
  }) async {
    final l10n = AppLocalizations.of(context);
    final personIdsToIgnore = selectedPersonIds.where((personID) {
      final person = personMap[personID];
      return person != null && !person.data.isIgnored;
    }).toList();
    final total = selectedClusterIds.length + personIdsToIgnore.length;
    if (total == 0) {
      widget.selectedPeople.clearAll();
      return;
    }

    final shouldShowProgressDialog = total > 1;
    final dialog = shouldShowProgressDialog
        ? createProgressDialog(
            context,
            _bulkIgnoreProgressMessage(l10n, 0, total),
          )
        : null;
    if (dialog != null) {
      await dialog.show();
    }
    var completed = 0;
    var hasUpdates = false;
    var completedAll = false;

    try {
      for (final clusterID in selectedClusterIds) {
        await ClusterFeedbackService.instance.ignoreCluster(
          clusterID,
          firePeopleChangedEvent: false,
        );
        completed++;
        hasUpdates = true;
        dialog?.update(
          message: _bulkIgnoreProgressMessage(l10n, completed, total),
        );
      }

      for (final personID in personIdsToIgnore) {
        final person = personMap[personID];
        if (person == null) continue;
        final ignoredPerson = person.copyWith(
          data: person.data.copyWith(isHidden: true),
        );
        await PersonService.instance.updatePerson(ignoredPerson);
        completed++;
        hasUpdates = true;
        dialog?.update(
          message: _bulkIgnoreProgressMessage(l10n, completed, total),
        );
      }

      completedAll = true;
    } finally {
      if (completedAll) {
        widget.selectedPeople.clearAll();
      }
      if (hasUpdates) {
        Bus.instance.fire(PeopleChangedEvent());
      }
      if (dialog != null) {
        await dialog.hide();
      }
    }
  }

  String _bulkIgnoreProgressMessage(
    AppLocalizations l10n,
    int completed,
    int total,
  ) {
    return "${l10n.pleaseWait} ($completed/$total)";
  }

  Future<void> _onShowPerson() async {
    final personMap = await personEntitiesMapFuture;
    final selectedPersonIds = _getSelectedPersonIds(personMap);
    if (selectedPersonIds.isEmpty) return;
    final ignoredSelectedPersonIds = selectedPersonIds
        .where((id) => personMap[id]?.data.isIgnored ?? false)
        .toList();
    if (ignoredSelectedPersonIds.length != selectedPersonIds.length) {
      return;
    }
    final multiple = ignoredSelectedPersonIds.length > 1;

    await showChoiceDialog(
      context,
      title: multiple
          ? AppLocalizations.of(
              context,
            ).areYouSureYouWantToShowThesePeopleInPeopleSectionAgain
          : AppLocalizations.of(
              context,
            ).areYouSureYouWantToShowThisPersonInPeopleSectionAgain,
      firstButtonLabel: multiple
          ? AppLocalizations.of(context).yesShowPeople
          : AppLocalizations.of(context).yesShowPerson,
      firstButtonOnTap: () async {
        try {
          for (final personID in ignoredSelectedPersonIds) {
            final person = personMap[personID];
            if (person == null) continue;
            if (_isUnnamedIgnoredPerson(person)) {
              await PersonService.instance.deletePerson(person.remoteID);
            } else {
              await PersonService.instance.updateAttributes(
                person.remoteID,
                isHidden: false,
              );
            }
          }
          Bus.instance.fire(PeopleChangedEvent());
          widget.selectedPeople.clearAll();
        } catch (e, s) {
          _logger.severe('Failed to show person(s)', e, s);
        }
      },
    );
  }

  Future<void> _onMerge() async {
    final personMap = await personEntitiesMapFuture;
    final selectedPersonIds = _getSelectedPersonIds(personMap);
    final selectedClusterIds = _getSelectedClusterIds();
    if (selectedClusterIds.isEmpty) return;

    if (!mounted) return;
    final namedSelectedPersonIds = _getNamedSelectedPersonIds(
      selectedPersonIds,
      personMap,
    );

    String? targetPersonId;
    PersonEntity? targetPerson;
    String? seedClusterId;
    if (namedSelectedPersonIds.length == 1) {
      targetPersonId = namedSelectedPersonIds.first;
      targetPerson = personMap[targetPersonId];
    } else {
      final initialPersons = await SearchService.instance.getAllFace(
        null,
        minClusterSize: kMinimumClusterSizeAllFaces,
      );
      if (!mounted) return;
      final namedPersons = initialPersons
          .where(
            (result) =>
                (result.params[kPersonParamID] as String?)?.isNotEmpty ?? false,
          )
          .toList();
      final selection = await showMergeClustersToPersonPage(
        context,
        initialPersons: namedPersons,
        seedClusterId: selectedClusterIds.first,
      );
      if (!mounted) return;
      targetPersonId = selection?.personId;
      seedClusterId = selection?.seedClusterId;
      targetPerson = selection?.person;
    }

    if (targetPersonId == null || targetPersonId.isEmpty) return;

    final person = targetPerson ?? personMap[targetPersonId];
    if (person == null) return;
    try {
      for (final clusterID in selectedClusterIds) {
        if (seedClusterId != null && clusterID == seedClusterId) {
          continue;
        }
        await ClusterFeedbackService.instance.addClusterToExistingPerson(
          clusterID: clusterID,
          person: person,
        );
      }
      widget.selectedPeople.clearAll();
    } catch (e, s) {
      _logger.severe('Merging clusters failed', e, s);
    }
  }
}
