import 'package:ente_components/ente_components.dart';
import 'package:ente_strings/ente_strings.dart';
import 'package:flutter/material.dart';
import 'package:locker/models/selected_collections.dart';
import 'package:locker/models/selected_files.dart';
import 'package:locker/services/collections/models/collection.dart';
import 'package:locker/services/files/sync/models/file.dart';
import 'package:locker/ui/components/item_list_view.dart';
import 'package:locker/ui/mixins/search_mixin.dart';

class SearchResultView extends StatelessWidget {
  final List<Collection> collections;
  final List<EnteFile> files;
  final String searchQuery;
  final bool isHomePage;
  final VoidCallback? onSearchEverywhere;
  final SelectedFiles selectedFiles;
  final SelectedCollections? selectedCollections;
  final VoidCallback? onFileSelectionStarted;
  final VoidCallback? onCollectionSelectionStarted;
  final bool selectionEnabled;
  final SearchScope searchScope;
  final ValueChanged<SearchScope>? onScopeChanged;

  const SearchResultView({
    super.key,
    required this.collections,
    required this.files,
    this.searchQuery = '',
    this.isHomePage = false,
    this.onSearchEverywhere,
    required this.selectedFiles,
    this.selectedCollections,
    this.onFileSelectionStarted,
    this.onCollectionSelectionStarted,
    this.selectionEnabled = true,
    this.searchScope = SearchScope.all,
    this.onScopeChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 16, bottom: Spacing.xxl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (onScopeChanged != null) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final scope in [
                    SearchScope.items,
                    SearchScope.collections,
                  ])
                    FilterChipComponent(
                      label: scope == SearchScope.items
                          ? context.strings.itemsLabel
                          : context.strings.collections,
                      state: searchScope == scope
                          ? FilterChipComponentState.selected
                          : FilterChipComponentState.unselected,
                      onChanged: (selected) =>
                          onScopeChanged!(selected ? scope : SearchScope.all),
                    ),
                ],
              ),
            ),
            const SizedBox(height: Spacing.lg),
          ],
          if (selectedCollections != null &&
              (selectedFiles.hasSelections ||
                  selectedCollections!.hasSelections))
            Padding(
              padding: const EdgeInsets.only(bottom: Spacing.lg),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  selectedCollections!.hasSelections
                      ? context.strings.collectionCount(
                          count: selectedCollections!.count,
                        )
                      : context.strings.itemCount(count: selectedFiles.count),
                  style: TextStyles.mini,
                ),
              ),
            ),
          ItemListView(
            files: files,
            collections: collections,
            selectedFiles: selectedFiles,
            selectedCollections: selectedCollections,
            onFileSelectionStarted: onFileSelectionStarted,
            onCollectionSelectionStarted: onCollectionSelectionStarted,
            selectionEnabled: selectionEnabled,
            filesFirst: true,
            showSectionHeaders: isHomePage,
            reserveSelectionPadding: false,
            emptyStateWidget: searchQuery.isNotEmpty
                ? FileListViewHelpers.createSearchEmptyState(
                    context: context,
                    searchQuery: searchQuery,
                  )
                : null,
          ),
          if (!isHomePage &&
              onSearchEverywhere != null &&
              searchQuery.isNotEmpty)
            FileListViewHelpers.createSearchEverywhereFooter(
              context: context,
              searchQuery: searchQuery,
              onTap: onSearchEverywhere!,
            ),
        ],
      ),
    );
  }
}
