import 'package:flutter/material.dart';

class EntePopupMenuItemAsync<T, U> extends PopupMenuItem<T> {
  final String Function(U?) label;
  final IconData Function(U?)? icon;
  final Widget Function(U?)? iconWidget;
  final Color? iconColor;
  final Color? labelColor;
  final Future<U> Function()? future;

  EntePopupMenuItemAsync(
    this.label, {
    required T super.value,
    this.icon,
    this.iconWidget,
    this.iconColor,
    this.labelColor,
    this.future,
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
         child: FutureBuilder<U>(
           future: future?.call(),
           builder: (context, snapshot) {
             return Row(
               children: [
                 if (iconWidget != null)
                   iconWidget(snapshot.data)
                 else if (icon != null)
                   Icon(icon(snapshot.data), color: iconColor),
                 const Padding(padding: EdgeInsets.all(8)),
                 Text(
                   label(snapshot.data),
                   style: TextStyle(color: labelColor),
                 ),
               ],
             );
           },
         ), // Initially empty, will be populated in build
       );
}
