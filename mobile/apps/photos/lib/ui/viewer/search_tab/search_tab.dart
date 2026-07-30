import "package:ente_components/theme/text_styles.dart";
import "package:fade_indexed_stack/fade_indexed_stack.dart";
import "package:flutter/foundation.dart";
import "package:flutter/material.dart";
import "package:flutter_animate/flutter_animate.dart";
import "package:logging/logging.dart";
import "package:photos/generated/intl/app_localizations.dart";
import "package:photos/models/search/generic_search_result.dart";
import "package:photos/models/search/index_of_indexed_stack.dart";
import "package:photos/models/search/search_result.dart";
import "package:photos/models/search/search_types.dart";
import "package:photos/service_locator.dart";
import "package:photos/services/wrapped/wrapped_service.dart";
import "package:photos/states/all_sections_examples_state.dart";
import "package:photos/theme/ente_theme.dart";
import "package:photos/ui/common/loading_widget.dart";
import "package:photos/ui/components/banners/ml_progress_banner.dart";
import "package:photos/ui/rituals/rituals_banner.dart";
import "package:photos/ui/viewer/search/result/no_result_widget.dart";
import "package:photos/ui/viewer/search/search_suggestions.dart";
import "package:photos/ui/viewer/search/search_widget.dart";
import "package:photos/ui/viewer/search/tab_empty_state.dart";
import "package:photos/ui/viewer/search_tab/contacts_section.dart";
import "package:photos/ui/viewer/search_tab/file_type_section.dart";
import "package:photos/ui/viewer/search_tab/locations_section.dart";
import "package:photos/ui/viewer/search_tab/magic_section.dart";
import "package:photos/ui/viewer/search_tab/people_section.dart";
import "package:photos/ui/viewer/search_tab/search_tab_horizontal_scroll.dart";
import "package:photos/ui/viewer/search_tab/search_tab_preview_limits.dart";
import "package:photos/ui/wrapped/wrapped_discovery_section.dart";

class SearchTab extends StatefulWidget {
  const SearchTab({super.key, this.shouldConsumeBackNotifier});

  final ValueNotifier<bool>? shouldConsumeBackNotifier;

  @override
  State<SearchTab> createState() => _SearchTabState();
}

class _SearchTabState extends State<SearchTab> {
  late int index;
  final indexOfStackNotifier = IndexOfStackNotifier();
  late final ValueNotifier<bool> _isSearchHeaderCollapsedNotifier;

  @override
  void initState() {
    super.initState();
    index = indexOfStackNotifier.index;
    _isSearchHeaderCollapsedNotifier = ValueNotifier(
      SearchWidgetState.query.trim().isNotEmpty,
    );
    indexOfStackNotifier.addListener(indexNotifierListener);
  }

  void indexNotifierListener() {
    setState(() {
      index = indexOfStackNotifier.index;
    });
  }

  void _setSearchHeaderCollapsed(bool isCollapsed) {
    if (_isSearchHeaderCollapsedNotifier.value == isCollapsed) {
      return;
    }
    _isSearchHeaderCollapsedNotifier.value = isCollapsed;
  }

  @override
  void dispose() {
    indexOfStackNotifier.removeListener(indexNotifierListener);
    _isSearchHeaderCollapsedNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = getEnteColorScheme(context);
    final resultsBackground = EnteTheme.isDark(context)
        ? colorScheme.backgroundColour
        : colorScheme.backgroundElevated2;
    final headerColor = index == 1
        ? resultsBackground
        : colorScheme.backgroundColour;
    return Column(
      children: [
        _SearchHeader(
          backgroundColor: headerColor,
          isCollapsedListenable: _isSearchHeaderCollapsedNotifier,
          searchField: SearchWidget(
            shouldConsumeBackNotifier: widget.shouldConsumeBackNotifier,
            onSearchInputActiveChanged: _setSearchHeaderCollapsed,
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final previewLimits = SearchTabPreviewLimits.forWidth(
                constraints.maxWidth,
              );
              return AllSectionsExamplesProvider(
                previewLimits: previewLimits,
                child: FadeIndexedStack(
                  lazy: false,
                  duration: const Duration(milliseconds: 150),
                  index: index,
                  children: [
                    AllSearchSections(previewLimits: previewLimits),
                    const SearchSuggestionsWidget(),
                    const NoResultWidget(),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _SearchHeader extends StatelessWidget {
  const _SearchHeader({
    required this.backgroundColor,
    required this.isCollapsedListenable,
    required this.searchField,
  });

  static const _horizontalPadding = 15.0;
  static const _topPadding = 12.0;
  static const _bottomPadding = 8.0;
  static const _expandedTitleGap = 16.0;
  static const _transitionDuration = Duration(milliseconds: 150);

  final Color backgroundColor;
  final ValueListenable<bool> isCollapsedListenable;
  final Widget searchField;

  @override
  Widget build(BuildContext context) {
    final colorScheme = getEnteColorScheme(context);
    final titleStyle = TextStyles.display1.copyWith(
      color: colorScheme.textBase,
    );
    return ColoredBox(
      color: backgroundColor,
      child: SafeArea(
        bottom: false,
        child: ValueListenableBuilder<bool>(
          valueListenable: isCollapsedListenable,
          child: searchField,
          builder: (context, isCollapsed, child) {
            return TweenAnimationBuilder<double>(
              tween: Tween(end: isCollapsed ? 1 : 0),
              duration: _transitionDuration,
              curve: Curves.easeOut,
              child: child,
              builder: (context, progress, child) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(
                    _horizontalPadding,
                    _topPadding,
                    _horizontalPadding,
                    _bottomPadding,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _SearchHeaderTitle(progress: progress, style: titleStyle),
                      SizedBox(height: _expandedTitleGap * (1 - progress)),
                      child!,
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _SearchHeaderTitle extends StatelessWidget {
  const _SearchHeaderTitle({required this.progress, required this.style});

  final double progress;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: Align(
        alignment: Alignment.topLeft,
        heightFactor: (1 - (progress * 1.35)).clamp(0.0, 1.0),
        child: Opacity(
          opacity: progress < 0.08 ? 1 : 0,
          child: Text(AppLocalizations.of(context).search, style: style),
        ),
      ),
    );
  }
}

class AllSearchSections extends StatefulWidget {
  final SearchTabPreviewLimits previewLimits;

  const AllSearchSections({super.key, required this.previewLimits});

  @override
  State<AllSearchSections> createState() => _AllSearchSectionsState();
}

class _AllSearchSectionsState extends State<AllSearchSections> {
  final Logger _logger = Logger('_AllSearchSectionsState');

  @override
  Widget build(BuildContext context) {
    const topPadding = 12.0;
    const bottomPadding = 124.0;

    return FutureBuilder<AllSectionsExamplesData>(
      future: InheritedAllSectionsExamples.of(
        context,
      ).allSectionsExamplesFuture,
      builder: (context, snapshot) {
        if (snapshot.hasData && snapshot.data!.sectionResults.isNotEmpty) {
          final sectionResults = snapshot.data!.sectionResults;
          final hasAnySearchableFiles = snapshot.data!.hasAnySearchableFiles;
          final shouldRenderContacts = !isLocalGalleryMode;
          if (!hasAnySearchableFiles &&
              sectionResults.every((element) => element.isEmpty) &&
              !shouldRenderContacts) {
            return const Padding(
              padding: EdgeInsets.only(bottom: 72),
              child: SearchTabEmptyState(),
            );
          }
          if (sectionResults.length != SectionType.values.length) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 72),
              child: Text(
                AppLocalizations.of(context).searchSectionsLengthMismatch(
                  snapshotLength: sectionResults.length,
                  searchLength: SectionType.values.length,
                ),
              ),
            );
          }
          final resultsBySection =
              Map<SectionType, List<SearchResult>>.fromIterables(
                SectionType.values,
                sectionResults,
              );
          List<GenericSearchResult> examplesFor(SectionType type) =>
              resultsBySection[type]! as List<GenericSearchResult>;

          final hasSurfacedOfflineFaces =
              isLocalGalleryMode &&
              resultsBySection[SectionType.face]!.isNotEmpty;
          final sectionWidgets = [
            if (hasGrantedMLConsent)
              PeopleSection(
                examples: examplesFor(SectionType.face),
                resultLimit: widget.previewLimits.faceResults,
              ),
            MagicSection(
              examplesFor(SectionType.magic),
              resultLimit: widget.previewLimits.magicResults,
            ),
            LocationsSection(
              examplesFor(SectionType.location),
              resultLimit: widget.previewLimits.locationResults,
            ),
            if (!isLocalGalleryMode)
              _RitualsDiscoverySection(
                resultLimit: widget.previewLimits.ritualResults,
              ),
            ValueListenableBuilder<WrappedEntryState>(
              valueListenable: wrappedService.stateListenable,
              builder: (BuildContext context, WrappedEntryState state, _) {
                if (!wrappedService.shouldShowDiscoveryEntry) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: searchTabSectionHorizontalPadding,
                  ),
                  child: WrappedDiscoverySection(state: state),
                );
              },
            ),
            ContactsSectionLoader(
              resultLimit: widget.previewLimits.contactResults,
            ),
            FileTypeSection(hasAnySearchableFiles: hasAnySearchableFiles),
          ];
          return ListView.builder(
                padding: const EdgeInsets.only(
                  top: topPadding,
                  bottom: bottomPadding,
                ),
                physics: const BouncingScrollPhysics(),
                itemCount: sectionWidgets.length + 1,
                itemBuilder: (context, index) {
                  if (index == 0) {
                    if (!isLocalGalleryMode) {
                      return const SizedBox.shrink();
                    }
                    if (hasSurfacedOfflineFaces) {
                      return const SizedBox.shrink();
                    }
                    return const Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: searchTabSectionHorizontalPadding,
                      ),
                      child: MLProgressBanner(),
                    );
                  }
                  return sectionWidgets[index - 1];
                },
              )
              .animate(delay: const Duration(milliseconds: 150))
              .slide(
                begin: const Offset(0, -0.015),
                end: const Offset(0, 0),
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOut,
              )
              .fadeIn(
                duration: const Duration(milliseconds: 150),
                curve: Curves.easeOut,
              );
        } else if (snapshot.hasError) {
          _logger.severe(
            'Failed to load sections: ',
            snapshot.error,
            snapshot.stackTrace,
          );
          if (kDebugMode) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 72),
              child: Text(
                AppLocalizations.of(context).error + ': ${snapshot.error}',
              ),
            );
          }
          return const Padding(
            padding: EdgeInsets.only(bottom: 72),
            child: EnteLoadingWidget(),
          );
        } else {
          return const Padding(
            padding: EdgeInsets.only(bottom: 72),
            child: EnteLoadingWidget(),
          );
        }
      },
    );
  }
}

class _RitualsDiscoverySection extends StatelessWidget {
  final int resultLimit;

  const _RitualsDiscoverySection({required this.resultLimit});

  @override
  Widget build(BuildContext context) {
    if (!flagService.ritualsFlag) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: RitualsBanner(resultLimit: resultLimit),
    );
  }
}
