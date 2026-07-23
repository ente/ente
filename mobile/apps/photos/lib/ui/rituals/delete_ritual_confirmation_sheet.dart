import "package:flutter/material.dart";
import "package:photos/theme/ente_theme.dart";

const _tightTextHeightBehavior = TextHeightBehavior(
  applyHeightToFirstAscent: false,
  applyHeightToLastDescent: false,
);

Future<bool> showDeleteRitualConfirmationSheet(BuildContext context) async {
  // Ensure any transient routes (like popup menus) have fully dismissed before
  // we attempt to show another modal route.
  await WidgetsBinding.instance.endOfFrame;
  if (!context.mounted) return false;

  final shouldDelete = await showModalBottomSheet<bool>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    builder: (_) => const _DeleteRitualConfirmationSheet(),
  );

  return shouldDelete == true;
}

class _DeleteRitualConfirmationSheet extends StatelessWidget {
  const _DeleteRitualConfirmationSheet();

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final colorScheme = getEnteColorScheme(context);
    final textTheme = getEnteTextTheme(context);

    final double bottomPadding =
        16 + mediaQuery.padding.bottom.clamp(0.0, 16.0).toDouble();

    return SafeArea(
      top: false,
      bottom: false,
      child: Padding(
        padding: EdgeInsets.only(left: 16, right: 16, bottom: bottomPadding),
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 480),
            decoration: BoxDecoration(
              color: colorScheme.backgroundElevated,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: colorScheme.strokeFaint, width: 1),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.12),
                  blurRadius: 24,
                  offset: const Offset(0, -6),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              children: [
                Positioned(
                  top: 6,
                  right: 6,
                  child: IconButton(
                    style: IconButton.styleFrom(
                      backgroundColor: colorScheme.fillFaint,
                      padding: const EdgeInsets.all(8),
                      shape: const CircleBorder(),
                      minimumSize: const Size(40, 40),
                    ),
                    onPressed: () => Navigator.of(context).pop(false),
                    icon: Icon(
                      Icons.close_rounded,
                      color: colorScheme.textBase,
                    ),
                    tooltip: MaterialLocalizations.of(
                      context,
                    ).closeButtonTooltip,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(height: 6),
                      Image.asset(
                        "assets/rituals/trash_rituals.png",
                        width: 170,
                        height: 170,
                        fit: BoxFit.contain,
                        filterQuality: FilterQuality.high,
                        errorBuilder: (context, error, stackTrace) => Icon(
                          Icons.delete_outline_rounded,
                          size: 96,
                          color: colorScheme.textFaint,
                        ),
                        excludeFromSemantics: true,
                      ),
                      const SizedBox(height: 18),
                      Text(
                        "Are you sure?",
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontFamily: "Nunito",
                          fontStyle: FontStyle.normal,
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.72,
                          height: 1.15,
                          decoration: TextDecoration.none,
                        ).copyWith(color: colorScheme.textBase),
                        textHeightBehavior: _tightTextHeightBehavior,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        "Deleting the ritual will not delete the album.",
                        textAlign: TextAlign.center,
                        style: textTheme.bodyMuted.copyWith(height: 1.4),
                        textHeightBehavior: _tightTextHeightBehavior,
                      ),
                      const SizedBox(height: 26),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFFF3B30),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                            padding: const EdgeInsets.symmetric(
                              vertical: 16,
                              horizontal: 12,
                            ),
                          ),
                          onPressed: () => Navigator.of(context).pop(true),
                          child: Text(
                            "Delete ritual",
                            style: textTheme.bodyBold.copyWith(
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
