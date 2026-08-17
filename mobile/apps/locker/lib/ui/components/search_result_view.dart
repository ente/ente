import 'package:flutter/material.dart';
import 'package:locker/services/collections/models/collection.dart';
import 'package:locker/services/files/sync/models/file.dart';
import 'package:locker/ui/components/item_list_view.dart';

class SearchResultView extends StatelessWidget {
  final List<Collection> collections;
  final List<EnteFile> files;
  final String searchQuery;
  final VoidCallback? onCollectionTap;
  final bool isHomePage;
  final VoidCallback? onSearchEverywhere;
  final bool showCollections;

  const SearchResultView({
    super.key,
    required this.collections,
    required this.files,
    this.searchQuery = '',
    this.onCollectionTap,
    this.isHomePage = false,
    this.onSearchEverywhere,
    this.showCollections = true,
  });

  @override
  Widget build(BuildContext context) {
    final displayCollections = showCollections ? collections : <Collection>[];

    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ItemListView(
            files: files,
            collections: displayCollections,
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
