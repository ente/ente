import "package:ente_components/ente_components.dart" as components;
import "package:flutter/material.dart";
import "package:photos/models/selected_people.dart";
import "package:photos/ui/components/bottom_action_bar/people_action_bar_widget.dart";
import "package:photos/ui/viewer/actions/people_selection_action_widget.dart";

class PeopleBottomActionBarWidget extends StatelessWidget {
  final SelectedPeople selectedPeople;
  final VoidCallback? onCancel;
  final Color? backgroundColor;
  final ScrollController? backgroundScrollController;

  const PeopleBottomActionBarWidget(
    this.selectedPeople, {
    super.key,
    this.backgroundColor,
    this.onCancel,
    this.backgroundScrollController,
  });

  @override
  Widget build(BuildContext context) {
    return PeopleSelectionActionWidget(
      selectedPeople,
      backgroundColor: backgroundColor,
      backgroundScrollController: backgroundScrollController,
      selectionControls: Padding(
        padding: const EdgeInsets.symmetric(horizontal: components.Spacing.sm),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Flexible(
              child: PeopleActionBarWidget(
                selectedPeople: selectedPeople,
                onCancel: onCancel,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
