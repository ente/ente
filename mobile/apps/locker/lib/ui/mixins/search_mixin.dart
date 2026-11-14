import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:locker/extensions/collection_extension.dart';
import 'package:locker/services/collections/models/collection.dart';
import 'package:locker/services/files/sync/models/file.dart';

enum SearchScope { all, items, collections }

mixin SearchMixin<T extends StatefulWidget> on State<T> {
  String _searchQuery = '';
  bool _isSearchActive = false;
  SearchScope _searchScope = SearchScope.all;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  List<Collection> get allCollections;
  List<EnteFile> get allFiles;

  void onSearchResultsChanged(
    List<Collection> collections,
    List<EnteFile> files,
  );

  void onSearchStateChanged(bool isActive) {}

  void onSearchFilterChanged() {}

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _activateSearch() {
    setState(() {
      _isSearchActive = true;
    });
    onSearchStateChanged(true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _searchFocusNode.requestFocus();
    });
  }

  void _deactivateSearch() {
    setState(() {
      _isSearchActive = false;
      _searchQuery = '';
      _searchScope = SearchScope.all;
    });
    _searchController.clear();
    onSearchStateChanged(false);
    _performSearch('');
  }

  void _clearSearch() {
    _searchController.clear();
    _onSearchChanged('');
  }

  void _onSearchChanged(String query) {
    if (!mounted) return;
    if (query != _searchQuery) onSearchFilterChanged();
    setState(() {
      _searchQuery = query;
    });
    _performSearch(query);
  }

  void _performSearch(String query) {
    if (!mounted) return;

    try {
      final normalizedQuery = query.trim().toLowerCase();
      final collections = _searchScope == SearchScope.items
          ? <Collection>[]
          : normalizedQuery.isEmpty
          ? allCollections
          : allCollections
                .where(
                  (collection) => _containsQuery(
                    collection.displayName ?? '',
                    normalizedQuery,
                  ),
                )
                .toList();
      final files = _searchScope == SearchScope.collections
          ? <EnteFile>[]
          : normalizedQuery.isEmpty
          ? allFiles
          : allFiles
                .where((file) => _searchInFile(file, normalizedQuery))
                .toList();
      onSearchResultsChanged(collections, files);
    } catch (e) {
      debugPrint('Search error: $e');
      if (mounted) {
        onSearchResultsChanged(const [], const []);
      }
    }
  }

  bool _searchInFile(EnteFile file, String query) {
    try {
      return _containsQuery(file.displayName, query) ||
          _containsQuery(file.title ?? '', query) ||
          _containsQuery(file.caption ?? '', query) ||
          _containsQuery(file.pubMagicMetadata.editedName ?? '', query) ||
          _containsQuery(file.pubMagicMetadata.uploaderName ?? '', query);
    } catch (_) {
      return false;
    }
  }

  bool _containsQuery(String text, String query) =>
      text.toLowerCase().contains(query);

  bool handleKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.escape) {
        if (_isSearchActive) {
          if (_searchQuery.isNotEmpty) {
            _clearSearch();
          } else {
            _deactivateSearch();
          }
          return true;
        }
      } else if (event.logicalKey == LogicalKeyboardKey.keyF &&
          (HardwareKeyboard.instance.isMetaPressed ||
              HardwareKeyboard.instance.isControlPressed)) {
        if (!_isSearchActive) {
          _activateSearch();
          return true;
        }
      }
    }
    return false;
  }

  String get searchQuery => _searchQuery;
  bool get isSearchActive => _isSearchActive;
  SearchScope get searchScope => _searchScope;
  TextEditingController get searchController => _searchController;
  FocusNode get searchFocusNode => _searchFocusNode;

  void updateSearchQuery(String query) => _onSearchChanged(query);

  void refreshSearch() => _performSearch(_searchQuery);

  void updateSearchScope(SearchScope scope) {
    if (scope == _searchScope) return;
    onSearchFilterChanged();
    _searchScope = scope;
    refreshSearch();
  }

  void activateSearchWithQuery(String query) {
    if (query != _searchQuery) onSearchFilterChanged();
    setState(() {
      _isSearchActive = true;
      _searchQuery = query;
    });
    _searchController.text = query;
    onSearchStateChanged(true);
    _performSearch(query);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _searchFocusNode.requestFocus();
    });
  }

  void dismissSearch() {
    if (_isSearchActive) {
      _deactivateSearch();
    }
  }
}
