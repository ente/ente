import "package:flutter/material.dart";

enum SearchState { empty, searching, notEmpty }

class IndexOfStackNotifier with ChangeNotifier {
  int _prevIndex = 0;
  int _index = 0;
  bool _isSearchQueryEmpty = true;
  SearchState _searchState = SearchState.empty;

  static IndexOfStackNotifier? _instance;

  IndexOfStackNotifier._();

  factory IndexOfStackNotifier() => _instance ??= IndexOfStackNotifier._();

  set isSearchQueryEmpty(bool value) {
    _isSearchQueryEmpty = value;
    setIndex();
  }

  set searchState(SearchState value) {
    _searchState = value;
    setIndex();
  }

  void setIndex() {
    _prevIndex = _index;

    if (_isSearchQueryEmpty) {
      _index = 0;
    } else {
      if (_searchState == SearchState.empty) {
        _index = 2;
      } else {
        _index = 1;
      }
    }
    _prevIndex != _index ? notifyListeners() : null;
  }

  int get index => _index;
}
