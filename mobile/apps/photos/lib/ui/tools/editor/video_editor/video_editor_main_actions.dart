import 'dart:math';

import "package:flutter/material.dart";

class VideoEditorMainActions extends StatelessWidget {
  const VideoEditorMainActions({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Align(
            alignment: Alignment.center,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minWidth: min(constraints.maxWidth, 600),
                  maxWidth: 600,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  mainAxisSize: MainAxisSize.min,
                  children: children,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
