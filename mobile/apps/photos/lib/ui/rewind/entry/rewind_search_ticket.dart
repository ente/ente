import "dart:math";

import "package:flutter/material.dart";
import "package:flutter/semantics.dart";
import "package:photos/service_locator.dart";
import "package:photos/services/rewind/rewind_edition.dart";
import "package:photos/ui/rewind/copy/rewind_copy.dart";
import "package:photos/ui/rewind/entry/rewind_entry.dart";
import "package:photos/ui/rewind/theme/rewind_assets.dart";
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
        if (entry == null || entry.dismissed) return const SizedBox.shrink();
        final copy = RewindCopy.of(context);
        final action = entry.completed
            ? copy.watchAgain
            : entry.opened
            ? copy.resume
            : copy.watch;
        return Dismissible(
          key: const ValueKey("rewind_search_ticket"),
          direction: DismissDirection.endToStart,
          onDismissed: (_) => entry.dismiss(),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: searchTabSectionHorizontalPadding,
              vertical: 8,
            ),
            child: Semantics(
              button: true,
              label: "Rewind ${RewindEdition.year}, $action",
              customSemanticsActions: {
                CustomSemanticsAction(label: copy.dismiss): entry.dismiss,
              },
              child: RewindPressable(
                onTap: () => entry.open(context),
                pressedScale: 0.97,
                child: const ExcludeSemantics(
                  child: ClipPath(
                    clipper: _TicketClipper(),
                    child: SizedBox(
                      height: _TicketArt.height,
                      child: _TicketArt(),
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

class _TicketArt extends StatelessWidget {
  const _TicketArt();

  static const height = 76.0;
  static const _width = 345.0;
  static const _wordmark = Rect.fromLTWH(25.98, 17.64, 158, 44);
  static const _ducky = Rect.fromLTWH(200, 6.82, 116, 70);

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const Positioned.fill(child: RewindDoodleTile()),
        Positioned.fill(
          child: LayoutBuilder(
            builder: (context, constraints) => FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.bottomCenter,
              child: SizedBox(
                width: max(constraints.maxWidth, _width),
                height: height,
                child: Stack(
                  children: [
                    Positioned.fromRect(
                      rect: _wordmark,
                      child: Image.file(
                        RewindAssets.file(RewindAssets.ticketWordmark),
                        fit: BoxFit.fill,
                      ),
                    ),
                    Positioned(
                      top: _ducky.top,
                      right: _width - _ducky.right,
                      width: _ducky.width,
                      height: _ducky.height,
                      child: Image.file(
                        RewindAssets.file(RewindAssets.ticketDucky),
                        fit: BoxFit.fill,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
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
