import 'package:flutter/material.dart';

List<Widget> addSeparators(List<Widget> listOfWidgets, Widget separator) {
  final int initialLength = listOfWidgets.length;
  final listOfWidgetsWithSeparators = <Widget>[];
  listOfWidgetsWithSeparators.addAll(listOfWidgets);
  for (var i = 1; i < initialLength; i++) {
    listOfWidgetsWithSeparators.insert((2 * i) - 1, separator);
  }
  return listOfWidgetsWithSeparators;
}
