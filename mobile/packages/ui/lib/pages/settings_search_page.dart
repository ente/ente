import 'dart:async';

import 'package:ente_components/ente_components.dart';
import 'package:ente_strings/ente_strings.dart';
import 'package:ente_ui/models/settings_search_item.dart';
import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

typedef SettingsSearchNavigation =
    FutureOr<void> Function(BuildContext context, WidgetBuilder routeBuilder);

class SettingsSearchPage extends StatefulWidget {
  const SettingsSearchPage({
    required this.items,
    required this.suggestions,
    required this.onNavigate,
    super.key,
  });

  final List<SettingsSearchItem> items;
  final List<SettingsSearchSuggestion> suggestions;
  final SettingsSearchNavigation onNavigate;

  @override
  State<SettingsSearchPage> createState() => _SettingsSearchPageState();
}

class _SettingsSearchPageState extends State<SettingsSearchPage> {
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  String _searchQuery = '';
  List<_SearchResultEntry> _filteredItems = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    setState(() {
      _searchQuery = query;
      if (query.isEmpty) {
        _filteredItems = [];
        return;
      }

      final sectionOrder = <String, int>{};
      for (var i = 0; i < widget.items.length; i++) {
        sectionOrder.putIfAbsent(
          _sectionKey(widget.items[i].sectionPath),
          () => i,
        );
      }

      final entries = <_SearchResultEntry>[];
      for (var i = 0; i < widget.items.length; i++) {
        final item = widget.items[i];
        final matchType = item.matchType(query);
        if (matchType == SettingsSearchMatchType.none) continue;

        final sectionKey = _sectionKey(item.sectionPath);
        entries.add(
          _SearchResultEntry(
            item: item,
            matchType: matchType,
            sectionKey: sectionKey,
            sectionOrder: sectionOrder[sectionKey] ?? i,
            itemOrder: i,
            sectionItemOrder: item.sectionItemPriority ?? 100 + i,
          ),
        );
      }

      final sectionsWithSubPageMatches = <String>{
        for (final entry in entries)
          if (entry.item.isSubPage) entry.sectionKey,
      };
      _filteredItems =
          entries
              .where(
                (entry) =>
                    !sectionsWithSubPageMatches.contains(entry.sectionKey) ||
                    entry.item.isSubPage,
              )
              .toList()
            ..sort(_compareResults);
    });
  }

  void _clearSearch() {
    _searchController.clear();
    _searchFocusNode.unfocus();
    _onSearchChanged('');
  }

  Future<void> _open(
    WidgetBuilder? routeBuilder,
    SettingsSearchAction? action,
  ) async {
    if (action != null) {
      await action(context);
    } else {
      await widget.onNavigate(context, routeBuilder!);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.componentColors.backgroundBase,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSearchBar(),
            Expanded(
              child: _searchQuery.isEmpty
                  ? _buildSuggestions()
                  : _buildSearchResults(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    final colors = context.componentColors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: TextInputComponent(
        controller: _searchController,
        focusNode: _searchFocusNode,
        hintText: context.strings.searchSettings,
        shouldUnfocusOnClearOrSubmit: true,
        onChanged: _onSearchChanged,
        prefix: HugeIcon(
          icon: HugeIcons.strokeRoundedSearch01,
          size: 20,
          color: colors.textLight,
          strokeWidth: 1.6,
        ),
        suffix: HugeIcon(
          icon: HugeIcons.strokeRoundedCancel01,
          size: 18,
          color: colors.textLight,
          strokeWidth: 1.6,
        ),
        onSuffixTap: _searchQuery.isNotEmpty
            ? _clearSearch
            : () => Navigator.of(context).pop(),
      ),
    );
  }

  Widget _buildSuggestions() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          Text(
            context.strings.suggestions,
            style: TextStyles.large.copyWith(
              color: context.componentColors.textBase,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final suggestion in widget.suggestions)
                FilterChipComponent(
                  label: suggestion.title,
                  onChanged: (_) =>
                      _open(suggestion.routeBuilder, suggestion.onTap),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSearchResults() {
    if (_filteredItems.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            context.strings.noResultsFound,
            style: TextStyles.body.copyWith(
              color: context.componentColors.textLight,
            ),
          ),
        ),
      );
    }

    final rows = _buildResultRows();
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: rows.length,
      itemBuilder: (_, index) => rows[index],
    );
  }

  List<Widget> _buildResultRows() {
    final sectionCounts = <String, int>{};
    for (final entry in _filteredItems) {
      sectionCounts.update(
        entry.sectionKey,
        (count) => count + 1,
        ifAbsent: () => 1,
      );
    }

    final rows = <Widget>[];
    String? currentSection;
    for (final entry in _filteredItems) {
      if (sectionCounts[entry.sectionKey]! >= 2 &&
          currentSection != entry.sectionKey) {
        currentSection = entry.sectionKey;
        rows.add(
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 8),
            child: Text(
              entry.sectionKey,
              style: TextStyles.large.copyWith(
                color: context.componentColors.textBase,
              ),
            ),
          ),
        );
      }
      rows.add(_buildSearchResultItem(entry.item));
    }
    return rows;
  }

  Widget _buildSearchResultItem(SettingsSearchItem item) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.sm),
      child: SettingsItem(
        title: item.title,
        subtitle: item.sectionPath != item.title ? item.sectionPath : null,
        icon: item.icon,
        subtitleMaxLines: 2,
        showOnlyLoadingState: true,
        onTap: () => _open(item.routeBuilder, item.onTap),
      ),
    );
  }

  static String _sectionKey(String sectionPath) {
    return sectionPath.split(' > ').first;
  }

  static int _compareResults(
    _SearchResultEntry first,
    _SearchResultEntry second,
  ) {
    var result = first.matchType.index.compareTo(second.matchType.index);
    if (result != 0) return result;
    result = first.sectionOrder.compareTo(second.sectionOrder);
    if (result != 0) return result;
    result = first.sectionItemOrder.compareTo(second.sectionItemOrder);
    if (result != 0) return result;
    return first.itemOrder.compareTo(second.itemOrder);
  }
}

class _SearchResultEntry {
  const _SearchResultEntry({
    required this.item,
    required this.matchType,
    required this.sectionKey,
    required this.sectionOrder,
    required this.itemOrder,
    required this.sectionItemOrder,
  });

  final SettingsSearchItem item;
  final SettingsSearchMatchType matchType;
  final String sectionKey;
  final int sectionOrder;
  final int itemOrder;
  final int sectionItemOrder;
}
