import "package:flutter/material.dart";
import "package:photos/models/search/hierarchical/face_filter.dart";
import "package:photos/models/search/hierarchical/hierarchical_search_filter.dart";
import "package:photos/models/search/hierarchical/only_them_filter.dart";
import "package:photos/ui/viewer/hierarchicial_search/chip_widgets/face_filter_chip.dart";
import "package:photos/ui/viewer/hierarchicial_search/chip_widgets/generic_filter_chip.dart";
import "package:photos/ui/viewer/hierarchicial_search/chip_widgets/only_them_filter_chip.dart";

class HierarchicalFilterChip extends StatelessWidget {
  final HierarchicalSearchFilter filter;
  final VoidCallback apply;
  final VoidCallback remove;
  final double? faceAvatarSize;

  const HierarchicalFilterChip({
    required this.filter,
    required this.apply,
    required this.remove,
    this.faceAvatarSize,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final filter = this.filter;
    if (filter is FaceFilter) {
      return FaceFilterChip(
        personId: filter.personId,
        clusterId: filter.clusterId,
        apply: apply,
        remove: remove,
        isApplied: filter.isApplied,
        avatarSize: faceAvatarSize,
      );
    }
    if (filter is OnlyThemFilter) {
      return OnlyThemFilterChip(
        faceFilters: filter.faceFilters,
        apply: apply,
        remove: remove,
        isApplied: filter.isApplied,
        avatarSize: faceAvatarSize,
      );
    }
    return GenericFilterChip(
      label: filter.name(),
      apply: apply,
      remove: remove,
      leadingIcon: filter.icon(),
      isApplied: filter.isApplied,
    );
  }
}
