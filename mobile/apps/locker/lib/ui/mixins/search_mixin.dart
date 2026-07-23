import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:locker/extensions/collection_extension.dart';
import 'package:locker/services/collections/collections_service.dart';
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
  bool _isSearching = false;
  Timer? _searchDebounceTimer;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  List<Collection> get allCollections;
  List<EnteFile> get allFiles;

  void onSearchResultsChanged(
    List<Collection> collections,
    List<EnteFile> files,
  );

  void onSearchStateChanged(bool isActive) {}

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    _searchDebounceTimer?.cancel();
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
    unawaited(_performSearch(''));
  }

  void _clearSearch() {
    _searchController.clear();
    _onSearchChanged('');
  }

  void _onSearchChanged(String query) {
    _searchDebounceTimer?.cancel();

    if (query.isEmpty && _searchQuery.isNotEmpty) {
      setState(() {
        _searchQuery = query;
      });
      unawaited(_performSearch(query));
      return;
    }

    _searchDebounceTimer = Timer(const Duration(milliseconds: 300), () {
      if (mounted) {
        setState(() {
          _searchQuery = query;
        });
        unawaited(_performSearch(query));
      }
    });
  }

  Future<void> _performSearch(String query) async {
    if (!mounted) return;

    setState(() {
      _isSearching = true;
    });

    try {
      final normalizedQuery = query.trim();
      if (normalizedQuery.isEmpty) {
        if (mounted) {
          onSearchResultsChanged(allCollections, allFiles);
        }
        return;
      }

      final List<Collection> filteredCollections = [];
      final List<EnteFile> collectionFiles = [];

      for (final collection in allCollections) {
        if (!mounted) return;
        final searchResult = await _searchInCollection(
          collection,
          normalizedQuery,
        );
        if (searchResult.matches) {
          filteredCollections.add(collection);
          if (searchResult.nameMatches) {
            collectionFiles.addAll(searchResult.files);
          }
        }
      }

      final Set<String> addedFileIds = collectionFiles
          .map((f) => f.uploadedFileID.toString())
          .toSet();
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
    } finally {
      if (mounted) {
        setState(() {
          _isSearching = false;
        });
      }
    }
  }

  Future<CollectionSearchResult> _searchInCollection(
    Collection collection,
    String query,
  ) async {
    try {
      final files = await CollectionService.instance.getFilesInCollection(
        collection,
      );
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

  bool _containsQuery(String text, String query) {
    if (text.isEmpty) return false;
    final lowerText = text.toLowerCase();
    final lowerQuery = query.trim().toLowerCase();
    if (lowerQuery.isEmpty) return false;

    if (lowerText.contains(lowerQuery)) {
      return true;
    }
    final words = lowerText.split(RegExp(r'[\s\-_\.]+'));
    return words.any((word) => word.startsWith(lowerQuery));
  }

  /// Handle keyboard shortcuts
  bool handleKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent) {
      // Clear search or close search on ESC
      if (event.logicalKey == LogicalKeyboardKey.escape) {
        if (_isSearchActive) {
          if (_searchQuery.isNotEmpty) {
            _clearSearch();
          } else {
            _deactivateSearch();
          }
          return true;
        }
      }
      // Activate search on Ctrl+F (Cmd+F on Mac)
      else if (event.logicalKey == LogicalKeyboardKey.keyF &&
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
  bool get isSearching => _isSearching;
  TextEditingController get searchController => _searchController;
  FocusNode get searchFocusNode => _searchFocusNode;

  void updateSearchQuery(String query) => _onSearchChanged(query);

  /// Programmatically activate search with a specific query
  void activateSearchWithQuery(String query) {
    setState(() {
      _isSearchActive = true;
      _searchQuery = query;
    });
    _searchController.text = query;
    onSearchStateChanged(true);
    unawaited(_performSearch(query));

    // Focus the search field after the widget is built
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _searchFocusNode.requestFocus();
    });
  }

  /// Programmatically dismiss the search UI and reset state
  void dismissSearch() {
    if (_isSearchActive) {
      _deactivateSearch();
    }
  }
}
