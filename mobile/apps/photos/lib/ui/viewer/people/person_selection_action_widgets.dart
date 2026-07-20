import "dart:async";

import "package:flutter/material.dart";
import "package:logging/logging.dart";
import "package:photos/core/configuration.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/events/people_changed_event.dart";
import "package:photos/events/people_sort_order_change_event.dart";
import "package:photos/generated/l10n.dart";
import "package:photos/l10n/l10n.dart";
import "package:photos/models/ml/face/person.dart";
import "package:photos/models/search/generic_search_result.dart";
import "package:photos/models/search/search_constants.dart";
import "package:photos/models/typedefs.dart";
import "package:photos/service_locator.dart";
import "package:photos/services/machine_learning/face_ml/face_filtering/face_filtering_constants.dart";
import "package:photos/services/machine_learning/face_ml/person/person_service.dart";
import "package:photos/services/search_service.dart";
import "package:photos/settings/local_settings.dart";
import "package:photos/theme/colors.dart";
import "package:photos/theme/ente_theme.dart";
import "package:photos/theme/text_style.dart";
import "package:photos/ui/common/loading_widget.dart";
import "package:photos/ui/components/buttons/button_widget.dart";
import "package:photos/ui/components/buttons/icon_button_widget.dart";
import "package:photos/ui/components/dialog_widget.dart";
import "package:photos/ui/components/models/button_type.dart";
import "package:photos/ui/components/searchable_appbar.dart";
import "package:photos/ui/notification/toast.dart";
import "package:photos/ui/viewer/people/face_thumbnail_squircle.dart";
import "package:photos/ui/viewer/people/person_face_widget.dart";
import "package:photos/utils/dialog_util.dart";
import "package:photos/utils/people_sort_util.dart";
import "package:photos/utils/person_contact_linking_util.dart";

class LinkContactToPersonSelectionPage extends StatefulWidget {
  final String emailToLink;
  const LinkContactToPersonSelectionPage({
    required this.emailToLink,
    super.key,
  });

  @override
  State<LinkContactToPersonSelectionPage> createState() =>
      _LinkContactToPersonSelectionPageState();
}

class _LinkContactToPersonSelectionPageState
    extends State<LinkContactToPersonSelectionPage> {
  late Future<List<_PersonSelectionEntry>> _personEntries;
  String _searchQuery = "";
  final _logger = Logger('LinkContactToPersonSelectionPage');
  late PeopleSortKey _sortKey;
  bool _nameSortAscending = true;
  bool _updatedSortAscending = false;
  bool _photosSortAscending = false;

  static const double _sortMenuItemHeight = 52;
  static const double _sortMenuCornerRadius = 12;

  @override
  void initState() {
    super.initState();

    final settings = localSettings;
    _sortKey = settings.peopleSortKey();
    _nameSortAscending = settings.peopleNameSortAscending;
    _updatedSortAscending = settings.peopleUpdatedSortAscending;
    _photosSortAscending = settings.peoplePhotosSortAscending;
    _personEntries = _loadPersonEntries();
  }

  Future<List<_PersonSelectionEntry>> _loadPersonEntries() async {
    final persons = await PersonService.instance.getPersons();
    final results = await SearchService.instance.getAllFace(
      null,
      minClusterSize: kMinimumClusterSizeAllFaces,
    );
    final resultsById = <String, GenericSearchResult>{};
    for (final result in results) {
      final personId = result.params[kPersonParamID] as String?;
      if (personId == null || personId.isEmpty) {
        continue;
      }
      resultsById[personId] = result;
    }

    final entries = <_PersonSelectionEntry>[];
    for (final person in persons) {
      final isAlreadyLinked =
          person.data.email != null && person.data.email!.isNotEmpty;
      if (person.data.isIgnored) {
        continue;
      }
      if (isAlreadyLinked) {
        continue;
      }
      final searchResult = resultsById[person.remoteID];
      if (searchResult == null) {
        continue;
      }
      entries.add(
        _PersonSelectionEntry(personEntity: person, searchResult: searchResult),
      );
    }
    return entries;
  }

  List<_PersonSelectionEntry> _filterPersons(
    List<_PersonSelectionEntry> persons,
  ) {
    final query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) {
      return persons;
    }
    return persons
        .where(
          (person) =>
              person.personEntity.data.name.toLowerCase().contains(query),
        )
        .toList();
  }

  void _updateSearchQuery(String value) {
    setState(() {
      _searchQuery = value;
    });
  }

  void _clearSearchQuery() {
    if (_searchQuery.isNotEmpty) {
      setState(() {
        _searchQuery = "";
      });
    }
  }

  bool _isSortAscending(PeopleSortKey key) {
    switch (key) {
      case PeopleSortKey.name:
        return _nameSortAscending;
      case PeopleSortKey.lastUpdated:
        return _updatedSortAscending;
      case PeopleSortKey.mostPhotos:
        return _photosSortAscending;
    }
  }

  bool _toggleSortDirection(PeopleSortKey key) {
    switch (key) {
      case PeopleSortKey.name:
        _nameSortAscending = !_nameSortAscending;
        return true;
      case PeopleSortKey.lastUpdated:
        _updatedSortAscending = !_updatedSortAscending;
        return true;
      case PeopleSortKey.mostPhotos:
        _photosSortAscending = !_photosSortAscending;
        return true;
    }
  }

  bool _canToggleSortDirection(PeopleSortKey key) {
    return key == PeopleSortKey.name ||
        key == PeopleSortKey.lastUpdated ||
        key == PeopleSortKey.mostPhotos;
  }

  void _sortFaces(List<GenericSearchResult> faces) {
    sortPeopleFaces(
      faces,
      PeopleSortConfig(
        sortKey: _sortKey,
        nameSortAscending: _nameSortAscending,
        updatedSortAscending: _updatedSortAscending,
        photosSortAscending: _photosSortAscending,
      ),
    );
  }

  Future<void> _persistSortPreferences() async {
    await localSettings.setPeopleSortKey(_sortKey);
    await localSettings.setPeopleNameSortAscending(_nameSortAscending);
    await localSettings.setPeopleUpdatedSortAscending(_updatedSortAscending);
    await localSettings.setPeoplePhotosSortAscending(_photosSortAscending);
    Bus.instance.fire(PeopleSortOrderChangeEvent());
  }

  List<_PersonSelectionEntry> _sortEntries(
    List<_PersonSelectionEntry> entries,
  ) {
    if (entries.isEmpty) {
      return entries;
    }
    final results = entries.map((entry) => entry.searchResult).toList();
    _sortFaces(results);
    final entryById = <String, _PersonSelectionEntry>{};
    for (final entry in entries) {
      final personId = entry.searchResult.params[kPersonParamID] as String?;
      if (personId == null || personId.isEmpty) {
        continue;
      }
      entryById[personId] = entry;
    }
    return results
        .map((result) {
          final personId = result.params[kPersonParamID] as String?;
          if (personId == null) {
            return null;
          }
          return entryById[personId];
        })
        .whereType<_PersonSelectionEntry>()
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    _logger.info("Building LinkContactToPersonSelectionPage");
    final textTheme = getEnteTextTheme(context);
    final colorScheme = getEnteColorScheme(context);
    final smallFontSize = textTheme.small.fontSize!;
    final textScaleFactor =
        MediaQuery.textScalerOf(context).scale(smallFontSize) / smallFontSize;
    const horizontalEdgePadding = 20.0;
    const gridPadding = 16.0;
    return Scaffold(
      body: FutureBuilder<List<_PersonSelectionEntry>>(
        future: _personEntries,
        builder: (context, snapshot) {
          final slivers = <Widget>[
            SearchableAppBar(
              title: Text(context.l10n.selectPersonToLink),
              onSearch: _updateSearchQuery,
              onSearchClosed: _clearSearchQuery,
              centerTitle: false,
              searchIconPadding: const EdgeInsets.fromLTRB(
                12,
                12,
                horizontalEdgePadding,
                12,
              ),
              actions: [
                Padding(
                  padding: const EdgeInsets.only(right: horizontalEdgePadding),
                  child: _buildSortMenu(context, textTheme, colorScheme),
                ),
              ],
            ),
          ];
          if (snapshot.connectionState == ConnectionState.waiting) {
            slivers.add(
              const SliverFillRemaining(
                child: Center(child: EnteLoadingWidget()),
              ),
            );
            return CustomScrollView(slivers: slivers);
          } else if (snapshot.hasError) {
            _logger.severe(
              "Failed to load _personEntities",
              snapshot.error,
              snapshot.stackTrace,
            );
            slivers.add(
              const SliverFillRemaining(
                child: Center(child: Icon(Icons.error_outline_rounded)),
              ),
            );
            return CustomScrollView(slivers: slivers);
          } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
            slivers.add(
              SliverFillRemaining(
                child: Center(
                  child: Text(
                    AppLocalizations.of(context).noResultsFound + '.',
                  ),
                ),
              ),
            );
            return CustomScrollView(slivers: slivers);
          }

          final sortedEntries = _sortEntries(snapshot.data!);
          final results = _filterPersons(sortedEntries);
          if (results.isEmpty) {
            slivers.add(
              SliverFillRemaining(
                child: Center(
                  child: Text(
                    AppLocalizations.of(context).noResultsFound + '.',
                  ),
                ),
              ),
            );
            return CustomScrollView(slivers: slivers);
          }

          final screenWidth = MediaQuery.of(context).size.width;
          final crossAxisCount = (screenWidth / 100).floor();
          final itemSize =
              (screenWidth -
                  ((horizontalEdgePadding * 2) +
                      ((crossAxisCount - 1) * gridPadding))) /
              crossAxisCount;

          slivers.add(
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                horizontalEdgePadding,
                16,
                horizontalEdgePadding,
                96,
              ),
              sliver: SliverGrid(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  mainAxisSpacing: gridPadding,
                  crossAxisSpacing: gridPadding,
                  crossAxisCount: crossAxisCount,
                  childAspectRatio:
                      itemSize / (itemSize + (24 * textScaleFactor)),
                ),
                delegate: SliverChildBuilderDelegate(
                  childCount: results.length,
                  (context, index) {
                    return _RoundedPersonFaceWidget(
                      key: ValueKey(results[index].personEntity.remoteID),
                      onTap: () async {
                        try {
                          final updatedPerson = await linkPersonToContact(
                            context,
                            emailToLink: widget.emailToLink,
                            personEntity: results[index].personEntity,
                          );

                          if (updatedPerson != null) {
                            if (!context.mounted) return;
                            Navigator.of(context).pop(updatedPerson);
                          }
                        } catch (e) {
                          _logger.severe("Failed to link person to contact", e);
                          if (!context.mounted) return;
                          await showGenericErrorDialog(
                            context: context,
                            error: e,
                          );
                        }
                      },
                      itemSize: itemSize,
                      personEntity: results[index].personEntity,
                    );
                  },
                ),
              ),
            ),
          );

          return CustomScrollView(slivers: slivers);
        },
      ),
    );
  }

  Widget _buildSortMenu(
    BuildContext context,
    EnteTextTheme textTheme,
    EnteColorScheme colorScheme,
  ) {
    return Theme(
      data: Theme.of(context).copyWith(
        highlightColor: Colors.transparent,
        splashColor: Colors.transparent,
      ),
      child: GestureDetector(
        onTapDown: (TapDownDetails details) async {
          final l10n = AppLocalizations.of(context);
          const sortKeys = PeopleSortKey.values;
          final PeopleSortKey? selectedKey = await showMenu<PeopleSortKey>(
            color: colorScheme.backgroundElevated,
            context: context,
            elevation: 0,
            shape: RoundedRectangleBorder(
              side: BorderSide(width: 0.5, color: colorScheme.strokeFaint),
              borderRadius: BorderRadius.circular(_sortMenuCornerRadius),
            ),
            position: RelativeRect.fromLTRB(
              details.globalPosition.dx,
              details.globalPosition.dy,
              details.globalPosition.dx,
              details.globalPosition.dy + 50,
            ),
            items: List.generate(sortKeys.length, (index) {
              final key = sortKeys[index];
              return _buildSortMenuItem(
                key,
                index == sortKeys.length - 1,
                textTheme,
                colorScheme,
                l10n,
              );
            }),
          );
          if (!mounted || selectedKey == null) {
            return;
          }
          if (selectedKey == _sortKey &&
              !_canToggleSortDirection(selectedKey)) {
            return;
          }
          setState(() {
            if (selectedKey == _sortKey) {
              _toggleSortDirection(selectedKey);
            } else {
              _sortKey = selectedKey;
            }
          });
          unawaited(_persistSortPreferences());
        },
        child: IconButtonWidget(
          icon: Icons.sort_rounded,
          iconButtonType: IconButtonType.secondary,
          iconColor: colorScheme.textMuted,
        ),
      ),
    );
  }

  PopupMenuItem<PeopleSortKey> _buildSortMenuItem(
    PeopleSortKey key,
    bool isLast,
    EnteTextTheme textTheme,
    EnteColorScheme colorScheme,
    AppLocalizations l10n,
  ) {
    String label;
    switch (key) {
      case PeopleSortKey.mostPhotos:
        label = l10n.photos;
        break;
      case PeopleSortKey.name:
        label = l10n.name;
        break;
      case PeopleSortKey.lastUpdated:
        label = l10n.updated;
        break;
    }

    String detail;
    switch (key) {
      case PeopleSortKey.mostPhotos:
        detail = l10n.count;
        break;
      case PeopleSortKey.name:
        detail = _isSortAscending(key) ? "A-Z" : "Z-A";
        break;
      case PeopleSortKey.lastUpdated:
        detail = _isSortAscending(key)
            ? l10n.sortOldestFirst
            : l10n.sortNewestFirst;
        break;
    }

    final bool isSelected = _sortKey == key;
    final bool isAscending = _isSortAscending(key);
    final IconData directionIcon = key == PeopleSortKey.name
        ? (isAscending ? Icons.arrow_downward : Icons.arrow_upward)
        : (isAscending ? Icons.arrow_upward : Icons.arrow_downward);

    return PopupMenuItem<PeopleSortKey>(
      value: key,
      padding: EdgeInsets.zero,
      height: _sortMenuItemHeight,
      child: Container(
        width: double.infinity,
        height: _sortMenuItemHeight,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          border: isLast
              ? null
              : Border(
                  bottom: BorderSide(
                    width: 0.5,
                    color: colorScheme.strokeFaint,
                  ),
                ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            Text(label, style: textTheme.mini),
            if (isSelected) ...[
              const SizedBox(width: 8),
              Container(
                width: 4,
                height: 4,
                decoration: BoxDecoration(
                  color: colorScheme.textMuted.withValues(alpha: 0.6),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(detail, style: textTheme.miniMuted),
              const SizedBox(width: 4),
              Icon(directionIcon, size: 16, color: colorScheme.textMuted),
            ],
          ],
        ),
      ),
    );
  }

  Future<PersonEntity?> linkPersonToContact(
    BuildContext context, {
    required String emailToLink,
    required PersonEntity personEntity,
  }) async {
    final linkedPerson = await findPersonLinkedToEmail(
      emailToLink,
      excludedPersonId: personEntity.remoteID,
    );
    if (linkedPerson != null) {
      if (!context.mounted) return null;
      await showAlreadyLinkedEmailDialog(
        context,
        emailToLink,
        linkedPerson: linkedPerson,
      );
      return null;
    }

    final personName = personEntity.data.name;
    PersonEntity? updatedPerson;
    if (!context.mounted) return null;
    final result = await showDialogWidget(
      context: context,
      title: context.l10n.linkPersonToEmail(email: emailToLink),
      icon: Icons.info_outline,
      body: context.l10n.linkPersonToEmailConfirmation(
        personName: personName,
        email: emailToLink,
      ),
      isDismissible: true,
      buttons: [
        ButtonWidget(
          buttonAction: ButtonAction.first,
          buttonType: ButtonType.neutral,
          labelText: context.l10n.link,
          isInAlert: true,
          onTap: () async {
            updatedPerson = await PersonService.instance.updateAttributes(
              personEntity.remoteID,
              email: emailToLink,
            );
            Bus.instance.fire(
              PeopleChangedEvent(
                type: PeopleEventType.saveOrEditPerson,
                source: "linkPersonToContact",
                person: updatedPerson,
              ),
            );
          },
        ),
        ButtonWidget(
          buttonAction: ButtonAction.cancel,
          buttonType: ButtonType.secondary,
          labelText: AppLocalizations.of(context).cancel,
          isInAlert: true,
        ),
      ],
    );

    if (result?.exception != null) {
      Logger(
        "linkPersonToContact",
      ).severe("Failed to link person to contact", result!.exception);
      if (!context.mounted) return null;
      await showGenericErrorDialog(context: context, error: result.exception);
      return null;
    } else {
      return updatedPerson;
    }
  }
}

class _PersonSelectionEntry {
  final PersonEntity personEntity;
  final GenericSearchResult searchResult;

  const _PersonSelectionEntry({
    required this.personEntity,
    required this.searchResult,
  });
}

class ReassignMeSelectionPage extends StatefulWidget {
  final String currentMeId;
  const ReassignMeSelectionPage({required this.currentMeId, super.key});

  @override
  State<ReassignMeSelectionPage> createState() =>
      _ReassignMeSelectionPageState();
}

class _ReassignMeSelectionPageState extends State<ReassignMeSelectionPage> {
  late Future<List<PersonEntity>> _personEntities;
  final _logger = Logger('ReassignMeSelectionPage');

  @override
  void initState() {
    super.initState();

    _personEntities = PersonService.instance.getPersons().then((persons) async {
      final List<PersonEntity> result = [];
      for (final person in persons) {
        if (person.data.userID != null ||
            (person.data.email != null && person.data.email!.isNotEmpty) ||
            (person.data.isIgnored)) {
          continue;
        }
        result.add(person);
      }
      return result;
    });
  }

  @override
  Widget build(BuildContext context) {
    _logger.info("Building ReassignMeSelectionPage");
    final smallFontSize = getEnteTextTheme(context).small.fontSize!;
    final textScaleFactor =
        MediaQuery.textScalerOf(context).scale(smallFontSize) / smallFontSize;
    const horizontalEdgePadding = 20.0;
    const gridPadding = 16.0;
    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.selectYourFace),
        centerTitle: false,
      ),
      body: FutureBuilder<List<PersonEntity>>(
        future: _personEntities,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: EnteLoadingWidget());
          } else if (snapshot.hasError) {
            _logger.severe(
              "Failed to load _personEntitiesWithThumnailFile",
              snapshot.error,
              snapshot.stackTrace,
            );
            return const Center(child: Icon(Icons.error_outline_rounded));
          } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return Center(
              child: Text(AppLocalizations.of(context).noResultsFound + '.'),
            );
          } else {
            final results = snapshot.data!;
            final screenWidth = MediaQuery.of(context).size.width;
            final crossAxisCount = (screenWidth / 100).floor();

            final itemSize =
                (screenWidth -
                    ((horizontalEdgePadding * 2) +
                        ((crossAxisCount - 1) * gridPadding))) /
                crossAxisCount;

            return GridView.builder(
              padding: const EdgeInsets.fromLTRB(
                horizontalEdgePadding,
                16,
                horizontalEdgePadding,
                96,
              ),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                mainAxisSpacing: gridPadding,
                crossAxisSpacing: gridPadding,
                crossAxisCount: crossAxisCount,
                childAspectRatio:
                    itemSize / (itemSize + (24 * textScaleFactor)),
              ),
              itemCount: results.length,
              itemBuilder: (context, index) {
                return _RoundedPersonFaceWidget(
                  key: ValueKey(results[index].remoteID),
                  onTap: () async {
                    final dialog = createProgressDialog(
                      context,
                      context.l10n.reassigningLoading,
                    );
                    unawaited(dialog.show());
                    try {
                      await reassignMe(
                        currentPersonID: widget.currentMeId,
                        newPersonID: results[index].remoteID,
                      );
                      if (!context.mounted) return;
                      showToast(
                        context,
                        context.l10n.reassignedToName(
                          name: results[index].data.name,
                        ),
                      );
                      await Future.delayed(const Duration(milliseconds: 1250));
                      unawaited(dialog.hide());
                      if (!context.mounted) return;
                      Navigator.of(context).pop();
                    } catch (e) {
                      unawaited(dialog.hide());
                      if (!context.mounted) return;
                      unawaited(
                        showGenericErrorDialog(context: context, error: e),
                      );
                    }
                  },
                  itemSize: itemSize,
                  personEntity: results[index],
                );
              },
            );
          }
        },
      ),
    );
  }

  Future<void> reassignMe({
    required String currentPersonID,
    required String newPersonID,
  }) async {
    try {
      final email = Configuration.instance.getEmail();
      final userID = Configuration.instance.getUserID();

      final updatedPerson1 = await PersonService.instance.updateAttributes(
        currentPersonID,
        email: null,
        userID: null,
      );
      Bus.instance.fire(
        PeopleChangedEvent(
          type: PeopleEventType.saveOrEditPerson,
          source: "reassignMe",
          person: updatedPerson1,
        ),
      );

      final updatedPerson2 = await PersonService.instance.updateAttributes(
        newPersonID,
        email: email,
        userID: userID,
      );
      Bus.instance.fire(
        PeopleChangedEvent(
          type: PeopleEventType.saveOrEditPerson,
          source: "reassignMe",
          person: updatedPerson2,
        ),
      );
    } catch (e) {
      _logger.severe("Failed to reassign me", e);
      rethrow;
    }
  }
}

class _RoundedPersonFaceWidget extends StatelessWidget {
  final FutureVoidCallback onTap;
  final double itemSize;
  final PersonEntity personEntity;

  const _RoundedPersonFaceWidget({
    super.key,
    required this.onTap,
    required this.itemSize,
    required this.personEntity,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              FaceThumbnailSquircleClip(
                child: Container(
                  width: itemSize,
                  height: itemSize,
                  decoration: BoxDecoration(
                    color: getEnteColorScheme(context).strokeFaint,
                  ),
                ),
              ),
              SizedBox(
                width: itemSize,
                height: itemSize,
                child: SizedBox(
                  width: itemSize - 2,
                  height: itemSize - 2,
                  child: FaceThumbnailSquircleClip(
                    child: PersonFaceWidget(
                      personId: personEntity.remoteID,
                      useFullFile: true,
                    ),
                  ),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 0),
            child: Text(
              personEntity.data.name,
              maxLines: 1,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: getEnteTextTheme(context).small,
            ),
          ),
        ],
      ),
    );
  }
}
