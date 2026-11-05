import "package:flutter/widgets.dart";

abstract class RewindPage {
  const RewindPage();

  String get key;

  int get stops => 1;

  bool get pinned => false;

  Widget build(BuildContext context, double position, {required bool isActive});
}
