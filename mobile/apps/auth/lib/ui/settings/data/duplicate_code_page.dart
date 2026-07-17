import 'package:ente_auth/l10n/l10n.dart';
import 'package:ente_auth/services/deduplication_service.dart';
import 'package:ente_auth/store/code_store.dart';
import 'package:ente_auth/ui/code_widget.dart';
import 'package:ente_auth/utils/dialog_util.dart';
import 'package:ente_components/ente_components.dart';
import 'package:ente_lock_screen/local_authentication_service.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';

class DuplicateCodePage extends StatefulWidget {
  const DuplicateCodePage({super.key, required this.duplicateCodes});

  final List<DuplicateCodes> duplicateCodes;

  @override
  State<DuplicateCodePage> createState() => _DuplicateCodePageState();
}

class _DuplicateCodePageState extends State<DuplicateCodePage> {
  final Logger _logger = Logger('DuplicateCodePage');
  final Set<int> selectedGroups = <int>{};
  late final List<DuplicateCodes> _duplicateCodes;

  @override
  void initState() {
    super.initState();
    _duplicateCodes = widget.duplicateCodes;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    return Semantics(
      container: true,
      identifier: 'auth_duplicate_codes_page',
      child: Scaffold(
        backgroundColor: colors.backgroundBase,
        body: AppBarComponent(
          title: context.l10n.deduplicateCodes,
          slivers: [
            SliverSafeArea(
              top: false,
              sliver: SliverList.list(children: _buildChildren(context)),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildChildren(BuildContext context) {
    final l10n = context.l10n;
    final allSelected = selectedGroups.length == _duplicateCodes.length;
    final children = <Widget>[
      Padding(
        padding: const EdgeInsets.fromLTRB(
          Spacing.lg,
          0,
          Spacing.lg,
          Spacing.lg,
        ),
        child: Align(
          alignment: AlignmentDirectional.centerEnd,
          child: Semantics(
            button: true,
            identifier: 'auth_duplicate_select_all',
            child: FilterChipComponent(
              label: allSelected ? l10n.deselectAll : l10n.selectAll,
              state: allSelected
                  ? FilterChipComponentState.selected
                  : FilterChipComponentState.unselected,
              onChanged: (_) => _toggleAll(),
            ),
          ),
        ),
      ),
    ];

    for (
      var groupIndex = 0;
      groupIndex < _duplicateCodes.length;
      groupIndex++
    ) {
      final codes = _duplicateCodes[groupIndex].codes;
      final isSelected = selectedGroups.contains(groupIndex);
      children.addAll([
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
          child: Semantics(
            button: true,
            identifier: 'auth_duplicate_group_$groupIndex',
            child: MenuGroupComponent(
              items: [
                MenuComponent(
                  title: '${codes.first.issuer} (${codes.length})',
                  selected: isSelected,
                  trailing: CheckboxComponent(
                    selected: isSelected,
                    onChanged: (_) => _toggleGroup(groupIndex),
                  ),
                  onTap: () => _toggleGroup(groupIndex),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: Spacing.sm),
        for (final code in codes) CodeWidget(code, isCompactMode: false),
        const SizedBox(height: Spacing.xl),
      ]);
    }

    final selectedItemsCount = _selectedItemsCount();
    if (selectedItemsCount > 0) {
      children.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(
            Spacing.lg,
            0,
            Spacing.lg,
            Spacing.xl,
          ),
          child: Semantics(
            button: true,
            identifier: 'auth_duplicate_trash',
            child: ButtonComponent(
              label: '${l10n.trash} ($selectedItemsCount)',
              variant: ButtonComponentVariant.critical,
              onTap: () => deleteDuplicates(selectedItemsCount),
            ),
          ),
        ),
      );
    }
    return children;
  }

  void _toggleAll() {
    setState(() {
      if (selectedGroups.length == _duplicateCodes.length) {
        selectedGroups.clear();
      } else {
        selectedGroups
          ..clear()
          ..addAll(List.generate(_duplicateCodes.length, (index) => index));
      }
    });
  }

  void _toggleGroup(int groupIndex) {
    setState(() {
      if (!selectedGroups.remove(groupIndex)) selectedGroups.add(groupIndex);
    });
  }

  int _selectedItemsCount() {
    var count = 0;
    for (final index in selectedGroups) {
      count += _duplicateCodes[index].codes.length - 1;
    }
    return count;
  }

  Future<void> deleteDuplicates(int itemCount) async {
    final isAuthSuccessful = await LocalAuthenticationService.instance
        .requestLocalAuthentication(
          context,
          context.l10n.deleteCodeAuthMessage,
        );
    if (!isAuthSuccessful || !mounted) return;

    final trashed = await showBottomSheetComponent<bool>(
      context: context,
      builder: (sheetContext) => Semantics(
        identifier: 'auth_duplicate_confirm_sheet',
        child: BottomSheetComponent(
          title: context.l10n.deleteDuplicates,
          message: context.l10n.moveMultipleToTrashMessage(itemCount),
          closeTooltip: context.l10n.close,
          actions: [
            ButtonComponent(
              label: context.l10n.trash,
              variant: ButtonComponentVariant.critical,
              onTap: () async {
                final didTrash = await _trashSelectedDuplicates();
                if (didTrash && sheetContext.mounted) {
                  Navigator.of(sheetContext).pop(true);
                }
              },
            ),
          ],
        ),
      ),
    );
    if (trashed == true && mounted) Navigator.of(context).pop();
  }

  Future<bool> _trashSelectedDuplicates() async {
    try {
      for (final index in selectedGroups) {
        final codes = _duplicateCodes[index].codes;
        for (var codeIndex = 1; codeIndex < codes.length; codeIndex++) {
          final code = codes[codeIndex];
          await CodeStore.instance.addCode(
            code.copyWith(display: code.display.copyWith(trashed: true)),
          );
        }
      }
      return true;
    } catch (error, stackTrace) {
      _logger.severe('Failed to trash duplicate codes', error, stackTrace);
      if (mounted) {
        showGenericErrorDialog(context: context, error: error).ignore();
      }
      return false;
    }
  }
}
