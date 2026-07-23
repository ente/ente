import 'package:ente_auth/l10n/l10n.dart';
import 'package:ente_auth/services/preference_service.dart';
import 'package:ente_components/ente_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class SortCodeMenuWidget extends StatelessWidget {
  const SortCodeMenuWidget({
    super.key,
    required this.currentKey,
    required this.onSelected,
    this.iconColor,
  });

  final CodeSortKey currentKey;
  final void Function(CodeSortKey) onSelected;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Semantics(
      button: true,
      label: l10n.editOrder,
      identifier: 'auth_sort_codes',
      child: IconButtonComponent(
        variant: IconButtonComponentVariant.unfilled,
        shouldSurfaceExecutionStates: false,
        tooltip: l10n.editOrder,
        icon: SvgPicture.asset(
          'assets/svg/filter-icon.svg',
          width: IconSizes.medium,
          height: IconSizes.medium,
          colorFilter: ColorFilter.mode(
            iconColor ?? context.componentColors.textBase,
            BlendMode.srcIn,
          ),
        ),
        onTap: () => _showSortOptions(context),
      ),
    );
  }

  Future<void> _showSortOptions(BuildContext context) {
    final l10n = context.l10n;
    return showBottomSheetComponent<void>(
      context: context,
      builder: (sheetContext) => Semantics(
        identifier: 'auth_sort_sheet',
        child: BottomSheetComponent(
          title: l10n.editOrder,
          closeTooltip: l10n.close,
          content: MenuGroupComponent(
            showDividers: true,
            items: [
              for (final key in CodeSortKey.values)
                MenuComponent(
                  title: _labelFor(l10n, key),
                  selected: key == currentKey,
                  trailing: RadioComponent(
                    selected: key == currentKey,
                    onChanged: (_) => _select(sheetContext, key),
                  ),
                  onTap: () => _select(sheetContext, key),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _select(BuildContext sheetContext, CodeSortKey key) {
    Navigator.of(sheetContext).pop();
    onSelected(key);
  }

  String _labelFor(AppLocalizations l10n, CodeSortKey key) {
    return switch (key) {
      CodeSortKey.issuerName => l10n.codeIssuerHint,
      CodeSortKey.accountName => l10n.account,
      CodeSortKey.mostFrequentlyUsed => l10n.mostFrequentlyUsed,
      CodeSortKey.recentlyUsed => l10n.mostRecentlyUsed,
      CodeSortKey.manual => l10n.manualSort,
    };
  }
}
