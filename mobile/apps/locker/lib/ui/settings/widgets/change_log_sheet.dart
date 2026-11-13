import "package:ente_components/ente_components.dart";
import "package:ente_strings/ente_strings.dart";
import "package:flutter/material.dart";
import "package:hugeicons/hugeicons.dart";
import "package:locker/ui/settings/widgets/change_log_strings.dart";

Future<void> showChangeLogSheet(BuildContext context) {
  final strings = ChangeLogStrings.forLocale(Localizations.localeOf(context));
  return showBottomSheetComponent<void>(
    context: context,
    builder: (_) => _ChangeLogSheet(strings: strings),
  );
}

class _ChangeLogSheet extends StatefulWidget {
  final ChangeLogStrings strings;

  const _ChangeLogSheet({required this.strings});

  @override
  State<_ChangeLogSheet> createState() => _ChangeLogSheetState();
}

class _ChangeLogSheetState extends State<_ChangeLogSheet> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    return BottomSheetComponent(
      header: _ChangeLogHeader(title: context.strings.whatsNew),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      actionsTopSpacing: Spacing.lg,
      content: Flexible(
        child: ScrollbarTheme(
          data: ScrollbarTheme.of(context).copyWith(
            thumbColor: WidgetStatePropertyAll(colors.fillDarkest),
            trackColor: WidgetStatePropertyAll(colors.fillDark),
            trackBorderColor: const WidgetStatePropertyAll(Colors.transparent),
          ),
          child: Scrollbar(
            controller: _scrollController,
            thumbVisibility: true,
            trackVisibility: true,
            thickness: 5,
            radius: const Radius.circular(39),
            child: ListView.separated(
              controller: _scrollController,
              shrinkWrap: true,
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.only(right: Spacing.lg),
              itemBuilder: (context, index) => _ChangeLogEntryTile(
                title: widget.strings.entries[index].title,
                description: widget.strings.entries[index].description,
              ),
              separatorBuilder: (_, _) => const SizedBox(height: Spacing.lg),
              itemCount: widget.strings.entries.length,
            ),
          ),
        ),
      ),
      actions: [
        ButtonComponent(
          variant: ButtonComponentVariant.primary,
          size: ButtonComponentSize.large,
          label: context.strings.continueLabel,
          shouldSurfaceExecutionStates: false,
          onTap: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}

class _ChangeLogEntryTile extends StatelessWidget {
  final String title;
  final String description;

  const _ChangeLogEntryTile({required this.title, required this.description});

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          textAlign: TextAlign.left,
          style: TextStyles.large.copyWith(color: colors.textBase),
        ),
        const SizedBox(height: Spacing.md),
        Text(
          description,
          textAlign: TextAlign.left,
          style: TextStyles.body.copyWith(color: colors.textLight),
        ),
      ],
    );
  }
}

class _ChangeLogHeader extends StatelessWidget {
  const _ChangeLogHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: IconButtonComponent(
            tooltip: "Close",
            variant: IconButtonComponentVariant.circular,
            shouldSurfaceExecutionStates: false,
            icon: const HugeIcon(
              icon: HugeIcons.strokeRoundedCancel01,
              size: IconSizes.small,
            ),
            onTap: () => Navigator.of(context).pop(),
          ),
        ),
        const SizedBox(height: Spacing.xs),
        Image.asset(
          "assets/whats_new_illustration.png",
          width: 115,
          height: 108,
        ),
        const SizedBox(height: Spacing.sm),
        Text(
          title,
          textAlign: TextAlign.center,
          style: TextStyles.display2.copyWith(color: colors.textBase),
        ),
      ],
    );
  }
}
