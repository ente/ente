import 'dart:async';

import 'package:flutter/material.dart';

typedef SettingsSearchAction = FutureOr<void> Function(BuildContext context);

class SettingsSearchItem {
  const SettingsSearchItem({
    required this.title,
    required this.sectionPath,
    this.subtitle,
    this.icon,
    this.routeBuilder,
    this.onTap,
    this.isSubPage = false,
    this.keywords = const [],
    this.sectionItemPriority,
  }) : assert(routeBuilder != null || onTap != null);

  final String title;
  final String sectionPath;
  final String? subtitle;
  final List<List<dynamic>>? icon;
  final WidgetBuilder? routeBuilder;
  final SettingsSearchAction? onTap;
  final bool isSubPage;
  final List<String> keywords;
  final int? sectionItemPriority;

  SettingsSearchMatchType matchType(String query) {
    final normalizedQuery = query.toLowerCase().trim();
    if (normalizedQuery.isEmpty) return SettingsSearchMatchType.none;

    final normalizedTitle = title.toLowerCase();
    if (normalizedTitle.startsWith(normalizedQuery)) {
      return SettingsSearchMatchType.titlePrefix;
    }
    if (normalizedTitle.contains(normalizedQuery)) {
      return SettingsSearchMatchType.title;
    }

    final normalizedSubtitle = subtitle?.toLowerCase();
    if (normalizedSubtitle?.startsWith(normalizedQuery) ?? false) {
      return SettingsSearchMatchType.subtitlePrefix;
    }
    if (normalizedSubtitle?.contains(normalizedQuery) ?? false) {
      return SettingsSearchMatchType.subtitle;
    }

    final normalizedSectionPath = sectionPath.toLowerCase();
    if (normalizedSectionPath.startsWith(normalizedQuery)) {
      return SettingsSearchMatchType.sectionPathPrefix;
    }
    if (normalizedSectionPath.contains(normalizedQuery)) {
      return SettingsSearchMatchType.sectionPath;
    }

    for (final keyword in keywords) {
      final normalizedKeyword = keyword.toLowerCase();
      if (normalizedKeyword.startsWith(normalizedQuery)) {
        return SettingsSearchMatchType.keywordPrefix;
      }
      if (normalizedKeyword.contains(normalizedQuery)) {
        return SettingsSearchMatchType.keyword;
      }
    }
    return SettingsSearchMatchType.none;
  }
}

enum SettingsSearchMatchType {
  titlePrefix,
  title,
  subtitlePrefix,
  subtitle,
  sectionPathPrefix,
  sectionPath,
  keywordPrefix,
  keyword,
  none,
}

class SettingsSearchSuggestion {
  const SettingsSearchSuggestion({
    required this.title,
    this.routeBuilder,
    this.onTap,
  }) : assert(routeBuilder != null || onTap != null);

  final String title;
  final WidgetBuilder? routeBuilder;
  final SettingsSearchAction? onTap;
}
