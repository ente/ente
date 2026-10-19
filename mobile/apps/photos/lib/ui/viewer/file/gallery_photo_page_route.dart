import "dart:ui" as ui;

import "package:flutter/material.dart";
import "package:photos/ui/viewer/file/hero_image.dart";

class GalleryPhotoPageRoute<T> extends PageRouteBuilder<T> {
  GalleryPhotoPageRoute({
    required Widget page,
    required Object tag,
    ui.Image? sourceImage,
    bool disableAnimations = false,
  }) : this._(
         page: page,
         tag: tag,
         sourceImage: sourceImage?.clone(),
         disableAnimations: disableAnimations,
       );

  GalleryPhotoPageRoute._({
    required Widget page,
    required Object tag,
    required ui.Image? sourceImage,
    required bool disableAnimations,
  }) : _sourceImage = sourceImage,
       super(
         pageBuilder: (_, _, _) =>
             ImageHeroSource(tag: tag, image: sourceImage, child: page),
         transitionDuration: disableAnimations
             ? Duration.zero
             : const Duration(milliseconds: 250),
         reverseTransitionDuration: disableAnimations
             ? Duration.zero
             : const Duration(milliseconds: 200),
       );

  final ui.Image? _sourceImage;
  CurvedAnimation? _fadeAnimation;

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => FadeTransition(
    opacity: _fadeAnimation ??= CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.linear,
    ),
    child: child,
  );

  @override
  void dispose() {
    _fadeAnimation?.dispose();
    _sourceImage?.dispose();
    super.dispose();
  }
}
