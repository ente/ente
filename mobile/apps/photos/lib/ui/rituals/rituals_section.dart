import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:flutter/material.dart";
import "package:hugeicons/hugeicons.dart";
import "package:photos/l10n/l10n.dart";
import "package:photos/models/rituals/ritual_models.dart";
import "package:photos/service_locator.dart";
import "package:photos/theme/ente_theme.dart";
import "package:photos/ui/rituals/all_rituals_screen.dart";
import "package:photos/ui/rituals/delete_ritual_confirmation_sheet.dart";
import "package:photos/ui/rituals/ritual_camera_page.dart";
import "package:photos/ui/rituals/ritual_editor_dialog.dart";

class RitualsSection extends StatelessWidget {
  const RitualsSection({
    required this.rituals,
    this.selectedRitualId,
    this.onSelectionChanged,
    this.showHeader = true,
    super.key,
  });

  final List<Ritual> rituals;
  final String? selectedRitualId;
  final ValueChanged<Ritual?>? onSelectionChanged;
  final bool showHeader;

  @override
  Widget build(BuildContext context) {
    final colorScheme = getEnteColorScheme(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showHeader) ...[
            Row(
              children: [
                Text(
                  context.l10n.ritualsTitle,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const Spacer(),
                IconButton(
                  onPressed: () async {
                    await showRitualEditor(context, ritual: null);
                  },
                  style: IconButton.styleFrom(
                    backgroundColor: colorScheme.fillFaint,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.all(8),
                    minimumSize: const Size(40, 40),
                  ),
                  icon: const HugeIcon(
                    icon: HugeIcons.strokeRoundedPlusSign,
                    size: 22,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ] else
            const SizedBox(height: 4),
          if (rituals.isEmpty)
            _CreateRitualCard(
              onTap: () async {
                await showRitualEditor(context, ritual: null);
              },
            )
          else
            Column(
              children: rituals
                  .map(
                    (ritual) => _RitualCard(
                      ritual: ritual,
                      isSelected: ritual.id == selectedRitualId,
                      onTap: () => onSelectionChanged?.call(ritual),
                    ),
                  )
                  .toList(),
            ),
        ],
      ),
    );
  }
}

class _CreateRitualCard extends StatelessWidget {
  const _CreateRitualCard({this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = getEnteColorScheme(context);
    final textTheme = getEnteTextTheme(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: colorScheme.backgroundElevated2,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.backgroundElevated2, width: 2),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: colorScheme.fillFaintPressed,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: HugeIcon(
                      icon: HugeIcons.strokeRoundedPlusSign,
                      color: colorScheme.textBase,
                      size: 24,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.l10n.ritualCreateYourOwn,
                        style: textTheme.body,
                      ),
                      Text(
                        context.l10n.ritualGetDailyReminders,
                        style: textTheme.smallMuted,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Icon(Icons.chevron_right_rounded, color: colorScheme.textMuted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RitualCard extends StatelessWidget {
  const _RitualCard({
    required this.ritual,
    this.isSelected = false,
    this.onTap,
  });

  final Ritual ritual;
  final bool isSelected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = getEnteColorScheme(context);
    final textTheme = getEnteTextTheme(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: colorScheme.backgroundElevated2,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isSelected
              ? colorScheme.primary500
              : colorScheme.backgroundElevated2,
          width: 2,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            if (onTap != null) {
              onTap!();
            } else {
              routeToPage(context, AllRitualsScreen(ritual: ritual));
            }
          },
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 0, 0),
            child: SizedBox(
              height: 64,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: colorScheme.fillFaintPressed,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: Text(
                        ritual.icon,
                        style: const TextStyle(
                          fontSize: 18,
                          height: 1,
                          decoration: TextDecoration.none,
                        ),
                        textHeightBehavior: _tightTextHeightBehavior,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          ritual.title.isEmpty
                              ? context.l10n.ritualUntitled
                              : ritual.title,
                          style: textTheme.body,
                          textHeightBehavior: _tightTextHeightBehavior,
                        ),
                        ritual.albumName == null || ritual.albumName!.isEmpty
                            ? Text(
                                context.l10n.ritualAlbumNotSet,
                                style: textTheme.smallMuted,
                                textHeightBehavior: _tightTextHeightBehavior,
                              )
                            : Text(
                                ritual.albumName!,
                                style: textTheme.smallMuted,
                                textHeightBehavior: _tightTextHeightBehavior,
                              ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: HugeIcon(
                      icon: HugeIcons.strokeRoundedCameraAdd01,
                      color: colorScheme.textBase,
                      size: 24,
                    ),
                    style: IconButton.styleFrom(
                      backgroundColor: colorScheme.fillFaint,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      padding: const EdgeInsets.all(8),
                      minimumSize: const Size(40, 40),
                    ),
                    onPressed: () => openRitualCamera(context, ritual),
                    tooltip: context.l10n.ritualOpenCameraTooltip,
                  ),
                  PopupMenuButton<String>(
                    padding: EdgeInsets.zero,
                    splashRadius: 20,
                    icon: Transform.translate(
                      offset: const Offset(4, 0),
                      child: const Icon(Icons.more_vert_rounded),
                    ),
                    elevation: 0,
                    color: colorScheme.backgroundElevated,
                    surfaceTintColor: colorScheme.backgroundElevated,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(
                        color: colorScheme.strokeFaint,
                        width: 0.5,
                      ),
                    ),
                    onSelected: (value) async {
                      switch (value) {
                        case "edit":
                          await showRitualEditor(context, ritual: ritual);
                          break;
                        case "delete":
                          final confirmed =
                              await showDeleteRitualConfirmationSheet(context);
                          if (!context.mounted || !confirmed) return;
                          await ritualsService.deleteRitual(ritual.id);
                          break;
                      }
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: "edit",
                        padding: EdgeInsets.zero,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                              child: Row(
                                children: [
                                  HugeIcon(
                                    icon: HugeIcons.strokeRoundedPencilEdit01,
                                    color: colorScheme.textBase,
                                    size: 22,
                                  ),
                                  const SizedBox(width: 10),
                                  Text(
                                    context.l10n.edit,
                                    style: getEnteTextTheme(context).body,
                                  ),
                                ],
                              ),
                            ),
                            Divider(
                              height: 0.5,
                              thickness: 0.5,
                              color: colorScheme.strokeFaint,
                              indent: 0,
                              endIndent: 0,
                            ),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: "delete",
                        padding: EdgeInsets.zero,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                          child: Row(
                            children: [
                              const HugeIcon(
                                icon: HugeIcons.strokeRoundedDelete02,
                                color: Colors.red,
                                size: 22,
                              ),
                              const SizedBox(width: 10),
                              Text(
                                context.l10n.delete,
                                style: getEnteTextTheme(
                                  context,
                                ).body.copyWith(color: Colors.red),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
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

const _tightTextHeightBehavior = TextHeightBehavior(
  applyHeightToFirstAscent: false,
  applyHeightToLastDescent: false,
);
