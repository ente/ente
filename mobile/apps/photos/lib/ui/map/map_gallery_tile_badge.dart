import "package:flutter/material.dart";
import "package:photos/theme/ente_theme.dart";

class MapGalleryTileBadge extends StatelessWidget {
  final int size;
  const MapGalleryTileBadge({super.key, required this.size});

  String formatNumber(int number) {
    if (number <= 99) {
      return number.toString();
    } else if (number <= 999) {
      return '${(number / 100).floor().toStringAsFixed(0)}00+';
    } else if (number >= 1000 && number < 2000) {
      return '1K+';
    } else {
      final int thousands = ((number - 1) ~/ 1000);
      return '${thousands}K+';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 0,
      right: 0,
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: const BoxDecoration(
          borderRadius: BorderRadius.all(Radius.circular(2)),
          shape: BoxShape.rectangle,
          // color: Color.fromRGBO(30, 215, 96, 1),
          color: Colors.green,
          // color: Colors.redAccent,
        ),
        child: Text(
          formatNumber(size),
          style: getEnteTextTheme(context).tinyBold,
        ),
      ),
    );
  }
}
