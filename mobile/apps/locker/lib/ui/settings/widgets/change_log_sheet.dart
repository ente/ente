import "package:ente_components/ente_components.dart";
import "package:flutter/material.dart";
import "package:locker/ui/settings/widgets/change_log_strings.dart";

class _ChangeLogEntry {
  final String title;
  final String description;

  const _ChangeLogEntry(this.title, this.description);
}

Future<void> showChangeLogSheet(BuildContext context) {
  final strings = ChangeLogStrings.forLocale(Localizations.localeOf(context));
  return showBottomSheetComponent<void>(
    context: context,
    builder: (sheetContext) => BottomSheetComponent(
      title: strings.sheetTitle,
      content: _ChangeLogSheetBody(strings: strings),
      actions: [
        ButtonComponent(
          label: strings.continueLabel,
          onTap: () => Navigator.of(sheetContext).pop(),
        ),
      ],
    ),
  );
}

class _ChangeLogSheetBody extends StatelessWidget {
  final ChangeLogStrings strings;

  const _ChangeLogSheetBody({required this.strings});

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.5;
    final entries =
        <_ChangeLogEntry>[
              _ChangeLogEntry(strings.title1, strings.desc1),
              _ChangeLogEntry(strings.title2, strings.desc2),
              _ChangeLogEntry(strings.title3, strings.desc3),
            ]
            .where(
              (entry) =>
                  entry.title.trim().isNotEmpty ||
                  entry.description.trim().isNotEmpty,
            )
            .toList(growable: false);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          strings.sheetSubtitle,
          style: TextStyles.body.copyWith(color: colors.textLight),
        ),
        const SizedBox(height: 16),
        ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: ListView.separated(
            shrinkWrap: true,
            physics: const BouncingScrollPhysics(),
            itemBuilder: (context, index) {
              final entry = entries[index];
              return _ChangeLogEntryTile(entry: entry);
            },
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemCount: entries.length,
          ),
        ),
      ],
    );
  }
}

class _ChangeLogEntryTile extends StatelessWidget {
  final _ChangeLogEntry entry;

  const _ChangeLogEntryTile({required this.entry});

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.fillLight,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(entry.title, style: TextStyles.bodyBold),
          const SizedBox(height: 6),
          Text(
            entry.description,
            style: TextStyles.body.copyWith(color: colors.textLight),
          ),
        ],
      ),
    );
  }
}
