import 'package:flutter/material.dart';
import "package:photos/generated/l10n.dart";
import "package:photos/models/search/search_result.dart";
import "package:photos/models/search/search_types.dart";
import "package:photos/states/all_sections_examples_state.dart";
import "package:photos/theme/ente_theme.dart";

class NoResultWidget extends StatefulWidget {
  const NoResultWidget({super.key});

  @override
  State<NoResultWidget> createState() => _NoResultWidgetState();
}

class _NoResultWidgetState extends State<NoResultWidget> {
  late final List<SectionType> searchTypes;
  final searchTypeToQuerySuggestion = <String, List<String>>{};
  @override
  void initState() {
    super.initState();
    searchTypes = SectionType.values.toList(growable: true);
    // remove face and content sectionType
    searchTypes.removeWhere(
      (type) => type == SectionType.magic || type == SectionType.wrapped,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    InheritedAllSectionsExamples.of(context).allSectionsExamplesFuture.then((
      value,
    ) {
      if (!mounted) return;
      final sectionResultsByType = value.sectionResults;
      if (sectionResultsByType.isEmpty) return;
      for (int i = 0; i < searchTypes.length; i++) {
        final SectionType sectionType = searchTypes[i];
        final int sectionIndex = SectionType.values.indexOf(sectionType);
        if (sectionIndex < 0 || sectionIndex >= sectionResultsByType.length) {
          continue;
        }
        final List<SearchResult> sectionResults =
            sectionResultsByType[sectionIndex];
        final querySuggestions = <String>[];
        for (int j = 0; j < 2 && j < sectionResults.length; j++) {
          querySuggestions.add(sectionResults[j].name());
        }
        if (querySuggestions.isNotEmpty) {
          searchTypeToQuerySuggestion.addAll({
            sectionType.sectionTitle(context): querySuggestions,
          });
        }
      }
      setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = getEnteTextTheme(context);
    const bottomPadding = 124.0;
    final searchTypeAndSuggestion = <Widget>[];
    searchTypeToQuerySuggestion.forEach((key, value) {
      searchTypeAndSuggestion.add(
        Row(
          children: [
            Text(key, style: textTheme.bodyMuted),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                formatList(value),
                style: textTheme.miniMuted,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      );
    });
    return Scaffold(
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(12, 0, 12, bottomPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppLocalizations.of(context).noResultsFound,
                  style: textTheme.largeBold,
                ),
                const SizedBox(height: 6),
                searchTypeToQuerySuggestion.isNotEmpty
                    ? Text(
                        AppLocalizations.of(
                          context,
                        ).modifyYourQueryOrTrySearchingFor,
                        style: textTheme.smallMuted,
                      )
                    : const SizedBox.shrink(),
              ],
            ),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: ListView.separated(
                itemBuilder: (context, index) {
                  return searchTypeAndSuggestion[index];
                },
                separatorBuilder: (context, index) {
                  return const SizedBox(height: 12);
                },
                itemCount: searchTypeToQuerySuggestion.length,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Join the strings with ', ' and wrap each element with double quotes
  String formatList(List<String> strings) {
    return strings.map((str) => '"$str"').join(', ');
  }
}
