import 'package:ente_components/ente_components.dart';
import 'package:ente_strings/ente_strings.dart';
import 'package:flutter/material.dart';
import 'package:locker/models/selected_files.dart';
import 'package:locker/services/collections/models/collection.dart';
import 'package:locker/services/files/sync/models/file.dart';
import 'package:locker/ui/components/item_list_view.dart';
import 'package:locker/ui/mixins/search_mixin.dart';

class SearchResultView extends StatelessWidget {
  final List<Collection> collections;
  final List<EnteFile> files;
  final String searchQuery;
  final VoidCallback? onCollectionTap;
  final bool isHomePage;
  final VoidCallback? onSearchEverywhere;
  final bool showCollections;
  final SelectedFiles? selectedFiles;
  final bool selectionEnabled;
  final SearchScope searchScope;
  final ValueChanged<SearchScope>? onScopeChanged;

  const SearchResultView({
    super.key,
    required this.collections,
    required this.files,
    this.searchQuery = '',
    this.onCollectionTap,
    this.isHomePage = false,
    this.onSearchEverywhere,
    this.showCollections = true,
    this.selectedFiles,
    this.selectionEnabled = true,
    this.searchScope = SearchScope.all,
    this.onScopeChanged,
  });

  @override
  Widget build(BuildContext context) {
    final displayCollections = showCollections ? collections : <Collection>[];

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        bottom: 24 + MediaQuery.of(context).padding.bottom,
      ),
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
            const SizedBox(height: 24),
          ],
          ItemListView(
            files: files,
            collections: displayCollections,
            selectedFiles: selectedFiles,
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
          if (selectedFiles != null && selectionEnabled)
            ListenableBuilder(
              listenable: selectedFiles!,
              builder: (context, _) =>
                  SizedBox(height: selectedFiles!.hasSelections ? 300 : 0),
            ),
        ],
      ),
    );
  }
}
