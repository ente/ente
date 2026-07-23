import "dart:async";

import "package:ente_components/theme/text_styles.dart";
import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:flutter/material.dart";
import "package:photos/events/event.dart";
import "package:photos/generated/l10n.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/ml/face/person.dart";
import "package:photos/models/search/generic_search_result.dart";
import "package:photos/models/search/recent_searches.dart";
import "package:photos/models/search/search_constants.dart";
import "package:photos/models/search/search_result.dart";
import "package:photos/models/search/search_types.dart";
import "package:photos/models/selected_people.dart";
import "package:photos/service_locator.dart" show isLocalGalleryMode;
import "package:photos/theme/ente_theme.dart";
import "package:photos/ui/settings/ml/machine_learning_settings_page.dart";
import "package:photos/ui/viewer/actions/select_all_status_icon.dart";
import "package:photos/ui/viewer/file/no_thumbnail_widget.dart";
import "package:photos/ui/viewer/file/thumbnail_widget.dart";
import "package:photos/ui/viewer/people/add_person_action_sheet.dart";
import "package:photos/ui/viewer/people/face_thumbnail_squircle.dart";
import "package:photos/ui/viewer/people/people_page.dart";
import 'package:photos/ui/viewer/people/person_face_widget.dart';
import "package:photos/ui/viewer/search/result/people_section_all_page.dart";
import "package:photos/ui/viewer/search/result/search_result_page.dart";
import "package:photos/ui/viewer/search_tab/search_tab_horizontal_scroll.dart";
import "package:photos/ui/viewer/search_tab/section_header.dart";

class PeopleSection extends StatefulWidget {
  final SectionType sectionType = SectionType.face;
  final List<GenericSearchResult> examples;
  final int resultLimit;

  const PeopleSection({
    super.key,
    required this.examples,
    required this.resultLimit,
  });

  @override
  State<PeopleSection> createState() => _PeopleSectionState();
}

class _PeopleSectionState extends State<PeopleSection> {
  late List<GenericSearchResult> _examples;
  final streamSubscriptions = <StreamSubscription>[];

  @override
  void initState() {
    super.initState();
    _examples = widget.examples;

    final streamsToListenTo = widget.sectionType.sectionUpdateEvents();
    for (Stream<Event> stream in streamsToListenTo) {
      streamSubscriptions.add(
        stream.listen((event) async {
          if (!mounted) return;
          final results = await widget.sectionType.getData(
            context,
            limit: widget.resultLimit + 1,
          );
          if (!mounted) return;
          _examples = results as List<GenericSearchResult>;
          setState(() {});
        }),
      );
    }
  }

  @override
  void dispose() {
    for (var subscriptions in streamSubscriptions) {
      subscriptions.cancel();
    }
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant PeopleSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    _examples = widget.examples;
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = getEnteTextTheme(context);
    final visibleExamples = _examples
        .take(widget.resultLimit)
        .toList(growable: false);
    return _examples.isNotEmpty
        ? GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              routeToPage(context, const PeopleSectionAllPage());
            },
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SectionHeader(widget.sectionType, hasMore: true),
                const SizedBox(height: 4),
                SearchExampleRow(visibleExamples, widget.sectionType),
                const SizedBox(height: 20),
              ],
            ),
          )
        : GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              routeToPage(context, const MachineLearningSettingsPage());
            },
            child: Padding(
              padding: const EdgeInsets.only(
                left: searchTabSectionHorizontalPadding,
                right: searchTabSectionHorizontalPadding,
                bottom: 20,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.sectionType.sectionTitle(context),
                          style: TextStyles.display3.copyWith(
                            color: textTheme.largeBold.color,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          widget.sectionType.getEmptyStateText(context),
                          style: textTheme.smallMuted,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
  }
}

class SearchExampleRow extends StatelessWidget {
  final SectionType sectionType;
  final List<GenericSearchResult> examples;

  const SearchExampleRow(this.examples, this.sectionType, {super.key});

  @override
  Widget build(BuildContext context) {
    return SearchTabHorizontalRow(
      spacing: 10,
      children: [
        for (final example in examples)
          PersonSearchExample(searchResult: example, selectedPeople: null),
      ],
    );
  }
}

class PersonSearchExample extends StatelessWidget {
  final GenericSearchResult searchResult;
  final double size;
  final SelectedPeople? selectedPeople;

  const PersonSearchExample({
    super.key,
    required this.searchResult,
    required this.selectedPeople,
    this.size = 108,
  });

  void toggleSelection() {
    selectedPeople?.toggleSelection(
      searchResult.params[kPersonParamID]! as String,
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isCluster =
        searchResult.type() == ResultType.faces &&
        searchResult.params.containsKey(kClusterParamId);

    return ListenableBuilder(
      listenable: selectedPeople ?? ValueNotifier(false),
      builder: (context, _) {
        final id = searchResult.params[kPersonParamID] as String?;
        final bool isSelected = id != null
            ? selectedPeople?.isPersonSelected(id) ?? false
            : false;

        return GestureDetector(
          onTap: selectedPeople != null
              ? toggleSelection
              : () {
                  RecentSearches().add(searchResult.name());
                  if (searchResult.onResultTap != null) {
                    searchResult.onResultTap!(context);
                  } else {
                    routeToPage(context, SearchResultPage(searchResult));
                  }
                },
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
                      width: size,
                      height: size,
                      decoration: BoxDecoration(
                        color: getEnteColorScheme(context).strokeFaint,
                      ),
                    ),
                  ),
                  Builder(
                    builder: (context) {
                      late Widget child;

                      if (searchResult.previewThumbnail() != null) {
                        child = searchResult.type() != ResultType.faces
                            ? ThumbnailWidget(
                                searchResult.previewThumbnail()!,
                                shouldShowSyncStatus: false,
                              )
                            : FaceSearchResult(
                                searchResult,
                                displaySize: size - 2,
                              );
                      } else {
                        child = const NoThumbnailWidget(addBorder: false);
                      }
                      return SizedBox(
                        width: size - 2,
                        height: size - 2,
                        child: FaceThumbnailSquircleClip(
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              child,
                              if (isSelected)
                                Container(
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.4),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                  Positioned(
                    top: 5,
                    right: 5,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      switchInCurve: Curves.easeOut,
                      switchOutCurve: Curves.easeIn,
                      child: isSelected
                          ? const SelectAllStatusIcon(
                              isSelected: true,
                              size: 18,
                              selectedFillColor: Colors.white,
                              selectedTickCutsOut: true,
                            )
                          : null,
                    ),
                  ),
                ],
              ),
              isCluster
                  ? isLocalGalleryMode
                        ? const SizedBox.shrink()
                        : GestureDetector(
                            behavior: HitTestBehavior.translucent,
                            onTap: () async {
                              final clusterId =
                                  searchResult.params[kClusterParamId]
                                      as String?;
                              final result = await showAssignPersonAction(
                                context,
                                clusterID: clusterId ?? searchResult.name(),
                              );
                              if (result != null &&
                                  result is (PersonEntity, EnteFile)) {
                                if (!context.mounted) return;
                                // ignore: unawaited_futures
                                routeToPage(
                                  context,
                                  PeoplePage(
                                    person: result.$1,
                                    searchResult: null,
                                  ),
                                );
                              } else if (result != null &&
                                  result is PersonEntity) {
                                if (!context.mounted) return;
                                // ignore: unawaited_futures
                                routeToPage(
                                  context,
                                  PeoplePage(
                                    person: result,
                                    searchResult: null,
                                  ),
                                );
                              }
                            },
                            child: Padding(
                              padding: const EdgeInsets.only(top: 6, bottom: 0),
                              child: Text(
                                AppLocalizations.of(context).addName,
                                maxLines: 1,
                                textAlign: TextAlign.center,
                                overflow: TextOverflow.ellipsis,
                                style: getEnteTextTheme(context).small,
                              ),
                            ),
                          )
                  : Padding(
                      padding: EdgeInsets.zero,
                      child: _PersonLabel(
                        name: searchResult.name(),
                        width: size,
                      ),
                    ),
            ],
          ),
        );
      },
    );
  }
}

class _PersonLabel extends StatelessWidget {
  const _PersonLabel({required this.name, required this.width});

  final String name;
  final double width;

  @override
  Widget build(BuildContext context) {
    final textTheme = getEnteTextTheme(context);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: SizedBox(
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyles.body.copyWith(color: textTheme.body.color),
            ),
          ],
        ),
      ),
    );
  }
}

class FaceSearchResult extends StatelessWidget {
  final SearchResult searchResult;
  final double displaySize;

  const FaceSearchResult(
    this.searchResult, {
    required this.displaySize,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final params = (searchResult as GenericSearchResult).params;
    final int cachedPixelWidth =
        (displaySize * MediaQuery.devicePixelRatioOf(context)).toInt();
    return PersonFaceWidget(
      personId: params[kPersonParamID],
      clusterID: params[kClusterParamId],
      cachedPixelWidth: cachedPixelWidth,
      key: params.containsKey(kPersonWidgetKey)
          ? ValueKey(params[kPersonWidgetKey])
          : ValueKey(params[kPersonParamID] ?? params[kClusterParamId]),
    );
  }
}
