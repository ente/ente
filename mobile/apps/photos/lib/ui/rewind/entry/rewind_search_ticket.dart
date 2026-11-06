import "package:flutter/material.dart";
import "package:photos/service_locator.dart";
import "package:photos/services/rewind/rewind_edition.dart";
import "package:photos/ui/rewind/entry/rewind_entry.dart";
import "package:photos/ui/rewind/theme/rewind_assets.dart";
import "package:photos/ui/rewind/theme/rewind_colors.dart";
import "package:photos/ui/rewind/theme/rewind_text_styles.dart";
import "package:photos/ui/rewind/widgets/rewind_backdrop.dart";
import "package:photos/ui/rewind/widgets/rewind_buttons.dart";
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
          child: Semantics(
            button: true,
            label: "Rewind ${RewindEdition.year}, $action",
            child: RewindPressable(
              onTap: () => entry.open(context),
              pressedScale: 0.97,
              child: ExcludeSemantics(
                child: ClipPath(
                  clipper: const _TicketClipper(),
                  child: SizedBox(
                    height: 76,
                    child: Stack(
                      children: [
                        const Positioned.fill(child: RewindDoodleTile()),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(18, 8, 16, 8),
                          child: Row(
                            children: [
                              Image.file(
                                RewindAssets.file(RewindAssets.tileLockup),
                                height: 60,
                                fit: BoxFit.contain,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  "YOUR YEAR.\nFULL VOLUME.",
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: RewindTextStyles.display(
                                    17,
                                    color: RewindColors.cream,
                                    height: 0.95,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              _ActionPill(action),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ActionPill extends StatelessWidget {
  const _ActionPill(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: RewindColors.cream,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: RewindColors.ink, width: 1.5),
        boxShadow: const [
          BoxShadow(color: RewindColors.ink, offset: Offset(2, 2.5)),
        ],
      ),
      child: Text(
        label,
        style: RewindTextStyles.body(13, color: RewindColors.ink, height: 1.1),
      ),
    );
  }
}

class _TicketClipper extends CustomClipper<Path> {
  const _TicketClipper();

  @override
  Path getClip(Size size) {
    final notch = size.height / 2;
    return Path.combine(
      PathOperation.difference,
      Path()..addRRect(
        RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(16)),
      ),
      Path()
        ..addOval(Rect.fromCircle(center: Offset(0, notch), radius: 8))
        ..addOval(
          Rect.fromCircle(center: Offset(size.width, notch), radius: 8),
        ),
    );
  }

  @override
  bool shouldReclip(_TicketClipper oldClipper) => false;
}
