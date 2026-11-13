import 'package:flutter/material.dart';

// Figma: https://www.figma.com/design/BuBNPPytxlVnqfmCUW0mgz/Ente-Visual-Design?node-id=2207-41577&m=dev
class Radii {
  const Radii._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double button = 20;
  static const double bottomSheet = 20;
  static const double sheet = 24;
  static const Radius buttonRadius = Radius.circular(button);
  static const BorderRadius buttonBorder = BorderRadius.all(buttonRadius);
}
