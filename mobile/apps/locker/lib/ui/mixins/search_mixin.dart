import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:locker/extensions/collection_extension.dart';
import 'package:locker/services/collections/models/collection.dart';
import 'package:locker/services/files/sync/models/file.dart';

class CollectionSearchResult {
  final bool matches;
  final bool nameMatches;
  final List<EnteFile> files;

  CollectionSearchResult({
    required this.matches,
    required this.nameMatches,
    required this.files,
  });
}

mixin SearchMixin<T extends StatefulWidget> on State<T> {
  String _searchQuery = '';
  bool _isSearchActive = false;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  List<Collection> get allCollections;
  List<EnteFile> get allFiles;
  Map<int, List<EnteFile>> get filesByCollection;

  void onSearchResultsChanged(
    List<Collection> collections,
    List<EnteFile> files,
  );

  void onSearchStateChanged(bool isActive) {}

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
    setState(() {
      _searchQuery = query;
    });
    _performSearch(query);
  }

  void _performSearch(String query) {
    if (!mounted) return;

    try {
      final normalizedQuery = query.trim().toLowerCase();
      if (normalizedQuery.isEmpty) {
        if (mounted) {
          onSearchResultsChanged(allCollections, allFiles);
        }
        return;
      }

      final List<Collection> filteredCollections = [];
      final List<EnteFile> collectionFiles = [];
      final Set<String> addedFileIds = {};

      for (final collection in allCollections) {
        if (!mounted) return;
        final searchResult = _searchInCollection(collection, normalizedQuery);
        if (searchResult.matches) {
          filteredCollections.add(collection);
          if (searchResult.nameMatches) {
            collectionFiles.addAll(
              searchResult.files.where(
                (file) => addedFileIds.add(file.uploadedFileID.toString()),
              ),
            );
          }
        }
      }

      final filteredFiles = allFiles.where((file) {
        if (addedFileIds.contains(file.uploadedFileID.toString())) {
          return false;
        }
        return _searchInFile(file, normalizedQuery);
      }).toList();

      final List<EnteFile> allFilteredFiles = [
        ...collectionFiles,
        ...filteredFiles,
      ];

      if (mounted) {
        onSearchResultsChanged(filteredCollections, allFilteredFiles);
      }
    } catch (e) {
      debugPrint('Search error: $e');
      if (mounted) {
        onSearchResultsChanged(allCollections, allFiles);
      }
    }
  }

  CollectionSearchResult _searchInCollection(
    Collection collection,
    String query,
  ) {
    try {
      final files = filesByCollection[collection.id] ?? const <EnteFile>[];
      final collectionNameMatches = _containsQuery(
        collection.displayName ?? '',
        query,
      );
      final fileMatches = files.any((file) => _searchInFile(file, query));

      return CollectionSearchResult(
        matches: collectionNameMatches || fileMatches,
        nameMatches: collectionNameMatches,
        files: collectionNameMatches ? files : [],
      );
    } catch (e) {
      debugPrint('Error searching in collection (ID: ${collection.id}): $e');
      final collectionNameMatches = _containsQuery(
        collection.displayName ?? '',
        query,
      );
      return CollectionSearchResult(
        matches: collectionNameMatches,
        nameMatches: collectionNameMatches,
        files: [],
      );
    }
  }

  bool _searchInFile(EnteFile file, String query) {
    return _containsQuery(file.displayName, query) ||
        _containsQuery(file.title ?? '', query) ||
        _containsQuery(file.caption ?? '', query) ||
        _containsQuery(file.pubMagicMetadata.editedName ?? '', query) ||
        _containsQuery(file.pubMagicMetadata.uploaderName ?? '', query);
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
  TextEditingController get searchController => _searchController;
  FocusNode get searchFocusNode => _searchFocusNode;

  void updateSearchQuery(String query) => _onSearchChanged(query);

  void refreshSearch() => _performSearch(_searchQuery);

  void activateSearchWithQuery(String query) {
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
