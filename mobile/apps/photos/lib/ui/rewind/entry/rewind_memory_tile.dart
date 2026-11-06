import "dart:math";

import "package:flutter/material.dart";
import "package:photos/services/rewind/rewind_edition.dart";
import "package:photos/ui/home/memories/memory_card_constants.dart";
import "package:photos/ui/rewind/entry/rewind_entry.dart";
import "package:photos/ui/rewind/theme/rewind_assets.dart";
import "package:photos/ui/rewind/theme/rewind_colors.dart";
import "package:photos/ui/rewind/theme/rewind_text_styles.dart";
import "package:photos/ui/rewind/widgets/rewind_backdrop.dart";
import "package:photos/ui/rewind/widgets/rewind_buttons.dart";
import "package:photos/ui/rewind/widgets/rewind_stickers.dart";

class RewindMemoryTile extends StatelessWidget {
  const RewindMemoryTile({
    required this.entry,
    required this.size,
    required this.onTap,
    super.key,
  });

  static const _design = Size(148, 215);

  final RewindEntry entry;
  final Size size;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final page = entry.resumeIndex + 1;
    final pages = entry.pages.length;
    final status = entry.completed
        ? "Watch again"
        : entry.started
        ? "Continue, $page of $pages"
        : "New";
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: kMemoryCardStripGap / 2),
      child: Semantics(
        button: true,
        label: "Rewind ${RewindEdition.year}, $status",
        child: RewindPressable(
          onTap: onTap,
          pressedScale: 0.96,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(kMemoryCardBorderRadius),
            child: SizedBox.fromSize(
              size: size,
              child: ExcludeSemantics(
                child: MediaQuery.withClampedTextScaling(
                  maxScaleFactor: 1.2,
                  child: FittedBox(
                    fit: BoxFit.cover,
                    child: SizedBox.fromSize(
                      size: _design,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          const Positioned.fill(child: RewindDoodleTile()),
                          Positioned.fromRect(
                            rect: const Rect.fromLTWH(12.73, 18.83, 120, 91),
                            child: Image.file(
                              RewindAssets.file(RewindAssets.tileLockup),
                              fit: BoxFit.contain,
                            ),
                          ),
                          Positioned.fromRect(
                            rect: const Rect.fromLTWH(
                              20.47,
                              118.83,
                              106.27,
                              119.4,
                            ),
                            child: Image.file(
                              RewindAssets.file(RewindAssets.tileDucky),
                              fit: BoxFit.contain,
                            ),
                          ),
                          if (!entry.opened)
                            Positioned(
                              right: 7,
                              bottom: 12,
                              child: Transform.rotate(
                                angle: -8 * pi / 180,
                                child: const RewindLabelSticker(
                                  "NEW",
                                  size: 13,
                                ),
                              ),
                            ),
                          if (entry.started)
                            _TileFooter(
                              label: "Continue",
                              detail: "$page of $pages",
                              progress: page / pages,
                            ),
                          if (entry.completed)
                            const _TileFooter(label: "Watch again"),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TileFooter extends StatelessWidget {
  const _TileFooter({required this.label, this.detail, this.progress});

  final String label;
  final String? detail;
  final double? progress;

  @override
  Widget build(BuildContext context) {
    final progress = this.progress;
    final detail = this.detail;
    return Positioned(
      left: 9,
      right: 9,
      bottom: 10,
      child: Container(
        padding: const EdgeInsets.fromLTRB(9, 6, 9, 7),
        decoration: BoxDecoration(
          color: RewindColors.cream,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: RewindColors.ink, width: 1.2),
          boxShadow: const [
            BoxShadow(color: RewindColors.ink, offset: Offset(1.5, 2)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text.rich(
                TextSpan(
                  text: label,
                  children: [
                    if (detail != null)
                      TextSpan(
                        text: "  $detail",
                        style: RewindTextStyles.body(
                          10.5,
                          weight: FontWeight.w500,
                          color: RewindColors.ink.withValues(alpha: 0.7),
                          height: 1.2,
                        ),
                      ),
                  ],
                ),
                style: RewindTextStyles.body(
                  12.5,
                  color: RewindColors.ink,
                  height: 1.2,
                ),
              ),
            ),
            if (progress != null) ...[
              const SizedBox(height: 5),
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 3,
                  color: RewindColors.hotPink,
                  backgroundColor: RewindColors.ink.withValues(alpha: 0.12),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
