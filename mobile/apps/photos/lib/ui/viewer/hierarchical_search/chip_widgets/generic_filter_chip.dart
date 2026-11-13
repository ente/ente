import "package:ente_components/ente_components.dart";
import "package:flutter/widgets.dart";
import "package:hugeicons/hugeicons.dart";
import "package:photos/models/search/hierarchical/hierarchical_search_filter.dart";

class GenericFilterChip extends StatelessWidget {
  final String label;
  final SearchFilterIcon? leadingIcon;
  final VoidCallback apply;
  final VoidCallback remove;
  final bool isApplied;

  const GenericFilterChip({
    required this.label,
    required this.apply,
    required this.remove,
    required this.isApplied,
    this.leadingIcon,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return FilterChipComponent(
      label: label,
      leading: leadingIcon == null
          ? null
          : HugeIcon(icon: leadingIcon!, size: IconSizes.small),
      state: isApplied
          ? FilterChipComponentState.selected
          : FilterChipComponentState.unselected,
      onChanged: (_) => isApplied ? remove() : apply(),
    );
  }
}
