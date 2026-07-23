import "package:ente_components/ente_components.dart" as components;
import "package:flutter/material.dart";
import "package:photos/generated/l10n.dart";
import "package:photos/models/selected_people.dart";

class PeopleActionBarWidget extends StatefulWidget {
  final SelectedPeople? selectedPeople;
  final VoidCallback? onCancel;
  const PeopleActionBarWidget({super.key, this.selectedPeople, this.onCancel});

  @override
  State<PeopleActionBarWidget> createState() => _PeopleActionBarWidgetState();
}

class _PeopleActionBarWidgetState extends State<PeopleActionBarWidget> {
  final ValueNotifier<int> _selectedPeopleNotifier = ValueNotifier(0);

  @override
  void initState() {
    super.initState();
    widget.selectedPeople?.addListener(_selectedPeopleListener);
  }

  @override
  void dispose() {
    widget.selectedPeople?.removeListener(_selectedPeopleListener);
    _selectedPeopleNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = components.ComponentTheme.colorsOf(context);
    final miniStyle = components.TextStyles.mini.copyWith(
      color: colors.textBase,
    );
    return SizedBox(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              flex: 1,
              child: ValueListenableBuilder(
                valueListenable: _selectedPeopleNotifier,
                builder: (context, value, child) {
                  final count = widget.selectedPeople?.personIds.length ?? 0;
                  return Text(
                    AppLocalizations.of(context).selectedPhotos(count: count),
                    style: miniStyle,
                  );
                },
              ),
            ),
            Flexible(
              flex: 1,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    widget.onCancel?.call();
                  },
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      AppLocalizations.of(context).cancel,
                      style: miniStyle,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _selectedPeopleListener() {
    _selectedPeopleNotifier.value =
        widget.selectedPeople?.personIds.length ?? 0;
  }
}
