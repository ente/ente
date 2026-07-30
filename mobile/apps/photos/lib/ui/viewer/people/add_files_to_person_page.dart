import "dart:async";

import "package:flutter/material.dart";
import "package:logging/logging.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/events/people_sort_order_change_event.dart";
import "package:photos/generated/l10n.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/search/generic_search_result.dart";
import "package:photos/models/search/search_constants.dart";
import "package:photos/service_locator.dart";
import "package:photos/services/machine_learning/face_ml/face_filtering/face_filtering_constants.dart";
import "package:photos/services/machine_learning/face_ml/person/person_service.dart";
import "package:photos/services/search_service.dart";
import "package:photos/settings/local_settings.dart";
import "package:photos/theme/colors.dart";
import "package:photos/theme/ente_theme.dart";
import "package:photos/theme/text_style.dart";
import "package:photos/ui/common/loading_widget.dart";
import "package:photos/ui/components/buttons/icon_button_widget.dart";
import "package:photos/ui/components/searchable_appbar.dart";
import "package:photos/ui/notification/toast.dart";
import "package:photos/ui/viewer/people/face_thumbnail_squircle.dart";
import "package:photos/ui/viewer/people/person_face_widget.dart";
import "package:photos/utils/dialog_util.dart";
import "package:photos/utils/people_sort_util.dart";

class AddFilesToPersonPage extends StatefulWidget {
  final List<EnteFile> files;
  final List<GenericSearchResult>? initialPersons;

  static final Logger _logger = Logger("AddFilesToPersonPage");

  const AddFilesToPersonPage({
    required this.files,
    this.initialPersons,
    super.key,
  });

  static Future<List<GenericSearchResult>> loadNamedPersons() async {
    final results = await SearchService.instance.getAllFace(
      null,
      minClusterSize: kMinimumClusterSizeAllFaces,
    );
    final named = results
        .where(
          (result) =>
              (result.params[kPersonParamID] as String?)?.isNotEmpty ?? false,
        )
        .toList();
    return named;
  }

  static Future<List<GenericSearchResult>?> prefetchNamedPersons(
    BuildContext context,
  ) async {
    try {
      final persons = await loadNamedPersons();
      if (!context.mounted) {
        return null;
      }
      if (persons.isEmpty) {
        showShortToast(
          context,
          AppLocalizations.of(context).pleaseNamePersonInPeopleSectionFirst,
        );
      }
      return persons;
    } catch (error, stackTrace) {
      _logger.severe(
        "Failed to load persons for manual tagging pre-check",
        error,
        stackTrace,
      );
      return null;
    }
  }

  static Future<bool> ensureNamedPersonsExist(BuildContext context) async {
    final persons = await prefetchNamedPersons(context);
    if (!context.mounted) {
      return false;
    }
    if (persons == null) {
      return true;
    }
    return persons.isNotEmpty;
  }

  @override
  State<AddFilesToPersonPage> createState() => _AddFilesToPersonPageState();
}

class _AddFilesToPersonPageState extends State<AddFilesToPersonPage> {
  late Future<List<GenericSearchResult>> _personsFuture;
  String _searchQuery = "";
  late PeopleSortKey _sortKey;
  bool _nameSortAscending = true;
  bool _updatedSortAscending = false;
  bool _photosSortAscending = false;

  static const double _sortMenuItemHeight = 52;
  static const double _sortMenuCornerRadius = 12;

  @override
  void initState() {
    super.initState();
    assert(widget.files.isNotEmpty);
    final settings = localSettings;
    _sortKey = settings.peopleSortKey();
    _nameSortAscending = settings.peopleNameSortAscending;
    _updatedSortAscending = settings.peopleUpdatedSortAscending;
    _photosSortAscending = settings.peoplePhotosSortAscending;
    _personsFuture = widget.initialPersons != null
        ? Future.value(widget.initialPersons!)
        : AddFilesToPersonPage.loadNamedPersons();
  }

  List<GenericSearchResult> _filterPersons(List<GenericSearchResult> persons) {
    final query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) {
      return persons;
    }
    return persons
        .where((person) => person.name().toLowerCase().contains(query))
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

  @override
  Widget build(BuildContext context) {
    final textTheme = getEnteTextTheme(context);
    final colorScheme = getEnteColorScheme(context);
    final smallFontSize = textTheme.small.fontSize!;
    final textScaleFactor =
        MediaQuery.textScalerOf(context).scale(smallFontSize) / smallFontSize;
    final textHeight = 24 * textScaleFactor;
    const horizontalEdgePadding = 20.0;
    const gridPadding = 16.0;

    return Scaffold(
      body: FutureBuilder<List<GenericSearchResult>>(
        future: _personsFuture,
        builder: (context, snapshot) {
          final slivers = <Widget>[
            SearchableAppBar(
              title: Text(AppLocalizations.of(context).addPerson),
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
            AddFilesToPersonPage._logger.severe(
              "Failed to load persons for manual tagging",
              snapshot.error,
              snapshot.stackTrace,
            );
            slivers.add(
              const SliverFillRemaining(
                child: Center(child: Icon(Icons.error_outline_rounded)),
              ),
            );
            return CustomScrollView(slivers: slivers);
          }

          final persons = snapshot.data ?? [];
          final sortedPersons = [...persons];
          _sortFaces(sortedPersons);
          final results = _filterPersons(sortedPersons);
          if (results.isEmpty) {
            slivers.add(
              SliverFillRemaining(
                child: Center(
                  child: Text(AppLocalizations.of(context).noResultsFound),
                ),
              ),
            );
            return CustomScrollView(slivers: slivers);
          }
          final screenWidth = MediaQuery.of(context).size.width;
          final estimatedCount = (screenWidth / 100).floor();
          final crossAxisCount = estimatedCount > 0 ? estimatedCount : 1;
          final itemSize =
              (screenWidth -
                  ((horizontalEdgePadding * 2) +
                      ((crossAxisCount - 1) * gridPadding))) /
              crossAxisCount;

          final bottomPadding = MediaQuery.paddingOf(context).bottom;
          slivers.add(
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                horizontalEdgePadding,
                16,
                horizontalEdgePadding,
                16 + bottomPadding,
              ),
              sliver: SliverGrid(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  mainAxisSpacing: gridPadding,
                  crossAxisSpacing: gridPadding,
                  crossAxisCount: crossAxisCount,
                  childAspectRatio: itemSize / (itemSize + textHeight),
                ),
                delegate: SliverChildBuilderDelegate(
                  childCount: results.length,
                  (context, index) {
                    final person = results[index];
                    final personId = person.params[kPersonParamID] as String?;
                    final personKey = personId != null && personId.isNotEmpty
                        ? personId
                        : person.name();
                    return _ManualPersonGridTile(
                      key: ValueKey(personKey),
                      result: person,
                      size: itemSize,
                      labelHeight: textHeight,
                      onTap: () => _onPersonSelected(person),
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

  Future<void> _onPersonSelected(GenericSearchResult result) async {
    final personId = result.params[kPersonParamID] as String?;
    if (personId == null || personId.isEmpty) {
      return;
    }
    final uploadIds = widget.files
        .map((file) => file.uploadedFileID)
        .whereType<int>()
        .toSet();
    if (uploadIds.isEmpty) {
      showShortToast(
        context,
        AppLocalizations.of(context).onlyUploadedFilesCanBeAddedToPerson,
      );
      return;
    }

    final dialog = createProgressDialog(
      context,
      AppLocalizations.of(context).saving,
    );
    await dialog.show();
    try {
      final result = await PersonService.instance.addManualFileAssignments(
        personID: personId,
        fileIDs: uploadIds,
      );
      await dialog.hide();
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(result);
    } catch (e, s) {
      await dialog.hide();
      AddFilesToPersonPage._logger.severe(
        "Failed to add files to person",
        e,
        s,
      );
      if (!mounted) {
        return;
      }
      await showGenericErrorDialog(context: context, error: e);
    }
  }
}

class _ManualPersonGridTile extends StatelessWidget {
  final GenericSearchResult result;
  final double size;
  final double labelHeight;
  final VoidCallback onTap;

  const _ManualPersonGridTile({
    super.key,
    required this.result,
    required this.size,
    required this.labelHeight,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final textStyle = getEnteTextTheme(context).small;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          FaceThumbnailSquircleClip(
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: getEnteColorScheme(context).strokeFaint,
              ),
              child: _FaceSearchResult(result: result),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              result.name(),
              maxLines: 1,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: textStyle,
            ),
          ),
        ],
      ),
    );
  }
}

class _FaceSearchResult extends StatelessWidget {
  final GenericSearchResult result;

  const _FaceSearchResult({required this.result});

  @override
  Widget build(BuildContext context) {
    final params = result.params;
    return PersonFaceWidget(
      personId: params[kPersonParamID],
      clusterID: params[kClusterParamId],
      key: params.containsKey(kPersonWidgetKey)
          ? ValueKey(params[kPersonWidgetKey])
          : ValueKey(params[kPersonParamID] ?? params[kClusterParamId]),
    );
  }
}
