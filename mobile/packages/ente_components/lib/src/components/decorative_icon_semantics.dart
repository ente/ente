import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:hugeicons/hugeicons.dart';

bool isDecorativeIcon(Widget icon) {
  return icon is HugeIcon ||
      (icon is SvgPicture && (icon.semanticsLabel?.isEmpty ?? true));
}
