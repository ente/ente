import "package:ente_components/ente_components.dart";
import "package:ente_strings/ente_strings.dart";
import "package:flutter/material.dart";
import "package:hugeicons/hugeicons.dart";
import "package:photos/models/selected_people.dart";
import "package:photos/ui/components/bottom_action_bar/action_bar_widget.dart";

class PeopleActionBarWidget extends StatelessWidget {
  const PeopleActionBarWidget({
    required this.selectedPeople,
    this.onCancel,
    super.key,
  });
  final SelectedPeople selectedPeople;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: selectedPeople,
    builder: (context, _) => SelectionControlChip(
      label: selectedPeople.personIds.length.toString(),
      semanticLabel:
          "${context.strings.cancel}, ${context.strings.selectedCount(count: selectedPeople.personIds.length)}",
      icon: const HugeIcon(
        icon: HugeIcons.strokeRoundedCancel01,
        size: IconSizes.small,
      ),
      onTap: onCancel,
    ),
  );
}
