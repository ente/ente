import "dart:math";

import "package:ente_components/hugeicons.dart";
import "package:flutter/material.dart";
import "package:flutter/semantics.dart";
import "package:photos/services/rewind/rewind_edition.dart";
import "package:photos/ui/home/memories/memory_card_constants.dart";
import "package:photos/ui/rewind/copy/rewind_copy.dart";
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
    this.onDismiss,
    super.key,
  });

  final RewindEntry entry;
  final Size size;
  final VoidCallback onTap;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final copy = RewindCopy.of(context);
    final onDismiss = this.onDismiss;
    final status = entry.completed
        ? copy.watchAgain
        : entry.started
        ? "${copy.resume}, "
              "${copy.progress(entry.resumeIndex + 1, entry.pageCount)}"
        : copy.newStatus;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: kMemoryCardStripGap / 2),
      child: Semantics(
        button: true,
        label: "Rewind ${RewindEdition.year}, $status",
        customSemanticsActions: onDismiss == null
            ? null
            : {CustomSemanticsAction(label: copy.dismiss): onDismiss},
        child: RewindPressable(
          onTap: onTap,
          pressedScale: 0.96,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(kMemoryCardBorderRadius),
            child: SizedBox.fromSize(
              size: size,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _TileArt(entry: entry),
                  if (onDismiss != null)
                    Positioned(
                      top: 0,
                      right: 0,
                      child: _DismissButton(
                        inset: size.height * 0.04,
                        onTap: onDismiss,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TileArt extends StatelessWidget {
  const _TileArt({required this.entry});

  static const _design = Size(148, 215);
  static const _lockup = Rect.fromLTWH(10.73, 14.83, 127, 96);
  static const _ducky = Rect.fromLTWH(16.65, 112.86, 122, 103);
  static const _replayLockup = Rect.fromLTWH(7, 11, 119, 90);
  static const _replayDucky = Rect.fromLTWH(5, 108, 137, 107);
  static const _replayDim = Color(0x52000000);

  final RewindEntry entry;

  @override
  Widget build(BuildContext context) {
    final copy = RewindCopy.of(context);
    final page = entry.resumeIndex + 1;
    final pages = entry.pageCount;
    final completed = entry.completed;
    return ExcludeSemantics(
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
                  rect: completed ? _replayLockup : _lockup,
                  child: Image.file(
                    RewindAssets.file(
                      completed
                          ? RewindAssets.tileReplayLockup
                          : RewindAssets.tileLockup,
                    ),
                    fit: BoxFit.fill,
                  ),
                ),
                if (completed)
                  const Positioned.fill(child: ColoredBox(color: _replayDim)),
                Positioned.fromRect(
                  rect: completed ? _replayDucky : _ducky,
                  child: Image.file(
                    RewindAssets.file(
                      completed
                          ? RewindAssets.tileReplayDucky
                          : RewindAssets.tileDucky,
                    ),
                    fit: BoxFit.fill,
                  ),
                ),
                if (!entry.opened)
                  Positioned(
                    right: 7,
                    bottom: 12,
                    child: Transform.rotate(
                      angle: -8 * pi / 180,
                      child: RewindLabelSticker(copy.newSticker, size: 13),
                    ),
                  ),
                if (entry.started)
                  _TileFooter(
                    label: copy.resume,
                    detail: copy.progress(page, pages),
                    progress: page / pages,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DismissButton extends StatelessWidget {
  const _DismissButton({required this.inset, required this.onTap});

  final double inset;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.all(inset),
          child: SizedBox.square(
            dimension: 16,
            child: DecoratedBox(
              decoration: const BoxDecoration(
                color: Color(0x4AFFFFFF),
                shape: BoxShape.circle,
              ),
              child: Transform.scale(
                scale: 0.75,
                child: const HugeIcon(
                  icon: HugeIcons.strokeRoundedCancel01,
                  color: Colors.white,
                  strokeWidth: 1.0 / 0.75,
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
