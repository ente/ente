import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:photos/models/file/file.dart";

/// Continuous zoom transform from the photo viewer.
///
/// [scale] is relative to the initial "contained" scale (1.0 = no zoom).
/// [offset] is the pan translation in logical pixels.
@immutable
class ZoomTransform {
  static const ZoomTransform identity = ZoomTransform(
    scale: 1.0,
    offset: Offset.zero,
  );

  final double scale;
  final Offset offset;

  const ZoomTransform({required this.scale, required this.offset});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ZoomTransform && other.scale == scale && other.offset == offset;

  @override
  int get hashCode => Object.hash(scale, offset);
}

enum FullScreenRequestReason { userInteraction, playbackStateChange }

typedef FullScreenRequestCallback =
    void Function(bool shouldEnable, FullScreenRequestReason reason);

String? detailPageFileIdentifier(EnteFile file) {
  if (file.uploadedFileID != null) {
    return "uploaded_${file.uploadedFileID}";
  }
  if (file.localID != null) {
    return "local_${file.localID}";
  }
  if (file.generatedID != null) {
    return "generated_${file.generatedID}";
  }
  return null;
}

class InheritedDetailPageState extends InheritedWidget {
  final ValueNotifier<bool> enableFullScreenNotifier;
  final ValueNotifier<bool> isInSharedCollectionNotifier;

  /// Holds the stable identifier of the file currently showing thumbnail
  /// fallback. Only the file with matching ID should display the indicator.
  final ValueNotifier<String?> showingThumbnailFallbackNotifier;

  /// Whether the photo viewer is currently zoomed in.
  final ValueNotifier<bool> isZoomedNotifier;

  /// Continuous zoom transform (scale + offset) from the photo viewer.
  /// Updated on every gesture frame so overlays can track the zoom.
  final ValueNotifier<ZoomTransform> zoomTransformNotifier;

  // Cannot be const because we accept a ValueNotifier instance at runtime
  // ignore: prefer_const_constructors_in_immutables
  InheritedDetailPageState({
    super.key,
    required super.child,
    required this.enableFullScreenNotifier,
    required this.isInSharedCollectionNotifier,
    required this.showingThumbnailFallbackNotifier,
    required this.isZoomedNotifier,
    required this.zoomTransformNotifier,
  });

  static InheritedDetailPageState of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<InheritedDetailPageState>()!;

  static InheritedDetailPageState? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<InheritedDetailPageState>();

  void toggleFullScreenByUser() {
    _applyFullScreenState(!enableFullScreenNotifier.value);
  }

  void requestFullScreen({
    required bool shouldEnable,
    required FullScreenRequestReason reason,
  }) {
    if (!shouldEnable && reason != FullScreenRequestReason.userInteraction) {
      return;
    }
    if (enableFullScreenNotifier.value == shouldEnable) {
      return;
    }
    _applyFullScreenState(shouldEnable);
  }

  void _applyFullScreenState(bool shouldEnable) {
    if (enableFullScreenNotifier.value == shouldEnable) {
      return;
    }
    enableFullScreenNotifier.value = shouldEnable;
    if (shouldEnable) {
      Future.delayed(const Duration(milliseconds: 200), () {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: []);
      });
    } else {
      SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.edgeToEdge,
        overlays: SystemUiOverlay.values,
      );
    }
  }

  @override
  bool updateShouldNotify(InheritedDetailPageState oldWidget) =>
      oldWidget.enableFullScreenNotifier != enableFullScreenNotifier ||
      oldWidget.isInSharedCollectionNotifier != isInSharedCollectionNotifier ||
      oldWidget.showingThumbnailFallbackNotifier !=
          showingThumbnailFallbackNotifier ||
      oldWidget.isZoomedNotifier != isZoomedNotifier ||
      oldWidget.zoomTransformNotifier != zoomTransformNotifier;
}
