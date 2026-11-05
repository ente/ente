import "package:flutter/material.dart";
import "package:photos/service_locator.dart";
import "package:photos/services/rewind/rewind_edition.dart";
import "package:photos/theme/ente_theme.dart";
import "package:photos/ui/rewind/entry/rewind_entry.dart";
import "package:photos/ui/viewer/search_tab/search_tab_horizontal_scroll.dart";

class RewindSearchTicket extends StatelessWidget {
  const RewindSearchTicket({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: rewindService.changes,
      builder: (context, _) {
        final entry = RewindEntry.current();
        if (entry == null) return const SizedBox.shrink();
        final textTheme = getEnteTextTheme(context);
        final action = entry.completed
            ? "Watch again"
            : entry.opened
            ? "Continue"
            : "Watch";
        return Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: searchTabSectionHorizontalPadding,
            vertical: 8,
          ),
          child: Material(
            color: const Color(0xFF1B1B3A),
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => entry.open(context),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        "Your ${RewindEdition.year} Rewind",
                        style: textTheme.bodyBold.copyWith(color: Colors.white),
                      ),
                    ),
                    Text(
                      action,
                      style: textTheme.small.copyWith(color: Colors.white),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
