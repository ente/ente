import 'package:flutter/material.dart';

class EntePopupMenuItem<T> extends PopupMenuItem<T> {
  final String label;
  final IconData? icon;
  final Widget? iconWidget;
  final Color? iconColor;
  final Color? labelColor;

  EntePopupMenuItem(
    this.label, {
    required T super.value,
    this.icon,
    this.iconWidget,
    this.iconColor,
    this.labelColor,
    super.key,
  }) : assert(
         icon != null || iconWidget != null,
         'Either icon or iconWidget must be provided.',
       ),
       assert(
         !(icon != null && iconWidget != null),
         'Only one of icon or iconWidget can be provided.',
       ),
       super(
         child: Row(
           children: [
             if (iconWidget != null)
               iconWidget
             else if (icon != null)
               Icon(icon, color: iconColor),
             const Padding(padding: EdgeInsets.all(8)),
             Text(label, style: TextStyle(color: labelColor)),
           ],
         ), // Initially empty, will be populated in build
       );
}
