import "dart:async";

import "package:ente_components/ente_components.dart";
import "package:ente_strings/ente_strings.dart";
import "package:ente_ui/components/loading_widget.dart";
import "package:flutter/material.dart";
import "package:hugeicons/hugeicons.dart";
import "package:logging/logging.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/events/people_sort_order_change_event.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/search/generic_search_result.dart";
import "package:photos/models/search/search_constants.dart";
import "package:photos/service_locator.dart";
import "package:photos/services/machine_learning/face_ml/face_filtering/face_filtering_constants.dart";
import "package:photos/services/machine_learning/face_ml/person/person_service.dart";
import "package:photos/services/search_service.dart";
import "package:photos/settings/local_settings.dart";
import "package:photos/theme/ente_theme.dart";
import "package:photos/ui/notification/toast.dart";
import "package:photos/ui/viewer/gallery/gallery_app_bar_actions.dart";
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
          context.strings.pleaseNamePersonInPeopleSectionFirst,
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
  static const _titleActionSize = 36.0;
  static const _searchTitleHeight = 52.0;
  static const _searchTransitionDuration = Duration(milliseconds: 240);

  late Future<List<GenericSearchResult>> _personsFuture;
  String _searchQuery = "";
  bool _isSearchBarVisible = false;
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  late PeopleSortKey _sortKey;
  bool _nameSortAscending = true;
  bool _updatedSortAscending = false;
  bool _photosSortAscending = false;

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

  void _activateSearch() {
    setState(() => _isSearchBarVisible = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _searchFocusNode.requestFocus();
      }
    });
  }

  void _closeSearch() {
    _searchFocusNode.unfocus();
    _searchController.clear();
    setState(() {
      _isSearchBarVisible = false;
      _searchQuery = "";
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
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
    final smallFontSize = textTheme.small.fontSize!;
    final textScaleFactor =
        MediaQuery.textScalerOf(context).scale(smallFontSize) / smallFontSize;
    final labelHeight = 28 * textScaleFactor;
    const horizontalEdgePadding = 20.0;
    const gridPadding = 16.0;

    return Scaffold(
      body: FutureBuilder<List<GenericSearchResult>>(
        future: _personsFuture,
        builder: (context, snapshot) {
          final slivers = <Widget>[];
          if (snapshot.connectionState == ConnectionState.waiting) {
            slivers.add(
              const SliverFillRemaining(
                child: Center(child: EnteLoadingWidget()),
              ),
            );
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
          } else {
            final persons = snapshot.data ?? [];
            final sortedPersons = [...persons];
            _sortFaces(sortedPersons);
            final results = _filterPersons(sortedPersons);
            if (results.isEmpty) {
              slivers.add(
                SliverFillRemaining(
                  child: Center(child: Text(context.strings.noResultsFound)),
                ),
              );
            } else {
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
                      childAspectRatio: itemSize / (itemSize + labelHeight),
                    ),
                    delegate: SliverChildBuilderDelegate(
                      childCount: results.length,
                      (context, index) {
                        final person = results[index];
                        final personId =
                            person.params[kPersonParamID] as String?;
                        final personKey =
                            personId != null && personId.isNotEmpty
                            ? personId
                            : person.name();
                        return _ManualPersonGridTile(
                          key: ValueKey(personKey),
                          result: person,
                          size: itemSize,
                          labelHeight: labelHeight,
                          onTap: () => _onPersonSelected(person),
                        );
                      },
                    ),
                  ),
                ),
              );
            }
          }

          return AppBarComponent(
            title: context.strings.addPerson,
            physics: const BouncingScrollPhysics(),
            titleBuilder: _buildTitle,
            titleBuilderHeight: _searchTitleHeight,
            slivers: slivers,
          );
        },
      ),
    );
  }

  Widget _buildTitle(BuildContext context, HeaderAppBarTitleState state) {
    return AnimatedSwitcher(
      duration: _searchTransitionDuration,
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      layoutBuilder: (currentChild, previousChildren) => Stack(
        alignment: Alignment.centerLeft,
        clipBehavior: Clip.none,
        children: [...previousChildren, ?currentChild],
      ),
      transitionBuilder: (child, animation) {
        final curvedAnimation = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        final beginOffset = child.key == const ValueKey("person_search_field")
            ? const Offset(0.035, 0)
            : const Offset(-0.035, 0);
        return FadeTransition(
          opacity: curvedAnimation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: beginOffset,
              end: Offset.zero,
            ).animate(curvedAnimation),
            child: child,
          ),
        );
      },
      child: _isSearchBarVisible
          ? KeyedSubtree(
              key: const ValueKey("person_search_field"),
              child: TextInputComponent(
                controller: _searchController,
                focusNode: _searchFocusNode,
                hintText: context.strings.search,
                autofocus: true,
                shouldUnfocusOnClearOrSubmit: true,
                prefix: HugeIcon(
                  icon: HugeIcons.strokeRoundedSearch01,
                  size: IconSizes.small,
                  color: context.componentColors.textLight,
                ),
                suffix: HugeIcon(
                  icon: HugeIcons.strokeRoundedCancel01,
                  size: IconSizes.small,
                  color: context.componentColors.textLight,
                ),
                onSuffixTap: _closeSearch,
                onChanged: _updateSearchQuery,
              ),
            )
          : KeyedSubtree(
              key: const ValueKey("person_title_row"),
              child: SizedBox(
                height: state.height,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Text(
                        state.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: state.textStyle,
                      ),
                    ),
                    const SizedBox(width: Spacing.md),
                    SizedBox.square(
                      dimension: _titleActionSize,
                      child: IconButtonComponent(
                        variant: IconButtonComponentVariant.primary,
                        shouldSurfaceExecutionStates: false,
                        icon: const HugeIcon(
                          icon: HugeIcons.strokeRoundedSearch01,
                        ),
                        onTap: _activateSearch,
                      ),
                    ),
                    const SizedBox(width: Spacing.sm),
                    SizedBox.square(
                      dimension: _titleActionSize,
                      child: galleryAppBarPopupMenuAction<PeopleSortKey>(
                        icon: const HugeIcon(
                          icon: HugeIcons.strokeRoundedFilterHorizontal,
                        ),
                        tooltip: context.strings.sort,
                        optionsBuilder: () => PeopleSortKey.values
                            .map(_buildSortMenuOption)
                            .toList(),
                        onSelected: _selectSortKey,
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  EntePopupMenuOption<PeopleSortKey> _buildSortMenuOption(PeopleSortKey key) {
    final l10n = context.strings;
    final isAscending = _isSortAscending(key);
    String label;
    String detail;
    switch (key) {
      case PeopleSortKey.mostPhotos:
        label = l10n.photos;
        detail = l10n.count;
        break;
      case PeopleSortKey.name:
        label = l10n.name;
        detail = isAscending ? l10n.sortAToZ : l10n.sortZToA;
        break;
      case PeopleSortKey.lastUpdated:
        label = l10n.updated;
        detail = isAscending ? l10n.sortOldestFirst : l10n.sortNewestFirst;
        break;
    }

    final isSelected = _sortKey == key;
    final directionIcon = key == PeopleSortKey.name
        ? (isAscending
              ? HugeIcons.strokeRoundedArrowDown02
              : HugeIcons.strokeRoundedArrowUp02)
        : (isAscending
              ? HugeIcons.strokeRoundedArrowUp02
              : HugeIcons.strokeRoundedArrowDown02);
    return EntePopupMenuOption(
      value: key,
      label: label,
      secondaryLabel: isSelected ? detail : null,
      isActive: isSelected,
      activeTrailingWidget: HugeIcon(
        icon: directionIcon,
        size: 12,
        strokeWidth: 3,
      ),
    );
  }

  void _selectSortKey(PeopleSortKey selectedKey) {
    setState(() {
      if (selectedKey == _sortKey) {
        _toggleSortDirection(selectedKey);
      } else {
        _sortKey = selectedKey;
      }
    });
    unawaited(_persistSortPreferences());
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
        context.strings.onlyUploadedFilesCanBeAddedToPerson,
      );
      return;
    }

    final dialog = createProgressDialog(context, context.strings.saving);
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
          SizedBox(
            height: labelHeight,
            child: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                result.name(),
                maxLines: 1,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: textStyle,
              ),
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
