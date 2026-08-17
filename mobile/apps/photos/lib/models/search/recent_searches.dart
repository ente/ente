import "package:flutter/material.dart";
import "package:photos/core/constants.dart";

class RecentSearches with ChangeNotifier {
  static RecentSearches? _instance;

  RecentSearches._();

  factory RecentSearches() => _instance ??= RecentSearches._();

  final searches = <String>{};

  void add(String query) {
    searches.add(query);
    while (searches.length > kSearchSectionLimit) {
      searches.remove(searches.first);
    }
    // Avoid surfacing the new search before the next screen opens.
    Future.delayed(const Duration(seconds: 1), () {
      notifyListeners();
    });
  }
}
