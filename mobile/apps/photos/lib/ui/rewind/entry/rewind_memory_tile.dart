import "package:flutter/material.dart";
import "package:photos/services/rewind/rewind_edition.dart";
import "package:photos/theme/ente_theme.dart";
import "package:photos/ui/home/memories/memory_card_constants.dart";
import "package:photos/ui/rewind/entry/rewind_entry.dart";

class RewindMemoryTile extends StatelessWidget {
  const RewindMemoryTile({
    required this.entry,
    required this.size,
    required this.onTap,
    super.key,
  });

  final RewindEntry entry;
  final Size size;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = getEnteTextTheme(context);
    final page = entry.resumeIndex + 1;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: kMemoryCardStripGap / 2),
      child: GestureDetector(
        onTap: onTap,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(kMemoryCardBorderRadius),
          child: Container(
            width: size.width,
            height: size.height,
            color: const Color(0xFF1B1B3A),
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!entry.opened)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      "New",
                      style: textTheme.miniBold.copyWith(color: Colors.black),
                    ),
                  ),
                const Spacer(),
                Text(
                  "Rewind ${RewindEdition.year}",
                  style: textTheme.bodyBold.copyWith(color: Colors.white),
                ),
                if (entry.started) ...[
                  const SizedBox(height: 6),
                  LinearProgressIndicator(
                    value: page / entry.pages.length,
                    minHeight: 3,
                    color: Colors.white,
                    backgroundColor: Colors.white24,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "Continue · $page of ${entry.pages.length}",
                    style: textTheme.mini.copyWith(color: Colors.white),
                  ),
                ],
                if (entry.completed) ...[
                  const SizedBox(height: 4),
                  Text(
                    "Watch again",
                    style: textTheme.mini.copyWith(color: Colors.white),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
