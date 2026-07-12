import 'package:ente_auth/l10n/l10n.dart';
import 'package:ente_auth/models/code.dart';
import 'package:ente_auth/services/deduplication_service.dart';
import 'package:ente_auth/store/code_store.dart';
import 'package:ente_auth/theme/ente_theme.dart';
import 'package:ente_auth/ui/code_widget.dart';
import 'package:ente_auth/utils/dialog_util.dart';
import 'package:ente_lock_screen/local_authentication_service.dart';
import 'package:ente_ui/components/centered_constrained_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:logging/logging.dart';

class DuplicateCodePage extends StatefulWidget {
  final List<DuplicateCodes> duplicateCodes;
  const DuplicateCodePage({super.key, required this.duplicateCodes});

  @override
  State<DuplicateCodePage> createState() => _DuplicateCodePageState();
}

class _DuplicateCodePageState extends State<DuplicateCodePage> {
  final Logger _logger = Logger("DuplicateCodePage");
  late List<DuplicateCodes> _duplicateCodes;
  final Set<int> selectedGrids = <int>{};

  @override
  void initState() {
    _duplicateCodes = widget.duplicateCodes;
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.deduplicateCodes), elevation: 0),
      body: CenteredConstrainedWidget(child: _getBody()),
    );
  }

  Widget _getBody() {
    final l10n = context.l10n;
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  GestureDetector(
                    onTap: () {
                      if (selectedGrids.length == _duplicateCodes.length) {
                        _removeAllGrids();
                      } else {
                        _selectAllGrids();
                      }
                      setState(() {});
                    },
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          selectedGrids.length == _duplicateCodes.length
                              ? l10n.deselectAll
                              : l10n.selectAll,
                          style: Theme.of(context).textTheme.titleMedium!
                              .copyWith(
                                fontSize: 14,
                                color: Theme.of(
                                  context,
                                ).iconTheme.color!.withValues(alpha: 0.7),
                              ),
                        ),
                        const Padding(padding: EdgeInsets.only(left: 4)),
                        selectedGrids.length == _duplicateCodes.length
                            ? const Icon(Icons.check_circle, size: 24)
                            : Icon(
                                Icons.check_circle_outlined,
                                color: getEnteColorScheme(context).strokeMuted,
                                size: 24,
                              ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.builder(
              itemCount: _duplicateCodes.length,
              shrinkWrap: true,
              itemBuilder: (context, index) {
                final List<Code> codes = _duplicateCodes[index].codes;
                return _getGridView(codes, index);
              },
            ),
          ),
          selectedGrids.isEmpty ? const SizedBox.shrink() : _getDeleteButton(),
        ],
      ),
    );
  }

  Widget _getGridView(List<Code> code, int itemIndex) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: GestureDetector(
            onTap: () {
              if (selectedGrids.contains(itemIndex)) {
                selectedGrids.remove(itemIndex);
              } else {
                selectedGrids.add(itemIndex);
              }
              setState(() {});
            },
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("${code[0].issuer}, ${code.length} items"),
                !selectedGrids.contains(itemIndex)
                    ? Icon(
                        Icons.check_circle_outlined,
                        color: getEnteColorScheme(context).strokeMuted,
                        size: 24,
                      )
                    : const Icon(Icons.check_circle, size: 24),
              ],
            ),
          ),
        ),
        AlignedGridView.count(
          crossAxisCount: (MediaQuery.sizeOf(context).width ~/ 400)
              .clamp(1, double.infinity)
              .toInt(),
          padding: const EdgeInsets.only(bottom: 40),
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemBuilder: (context, index) {
            return CodeWidget(
              key: ValueKey('${code.hashCode}_$index'),
              code[index],
              isCompactMode: false,
            );
          },
          itemCount: code.length,
        ),
      ],
    );
  }

  Widget _getDeleteButton() {
    int selectedItemsCount = 0;
    for (int idx = 0; idx < _duplicateCodes.length; idx++) {
      if (selectedGrids.contains(idx)) {
        selectedItemsCount += _duplicateCodes[idx].codes.length - 1;
      }
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 20),
      child: SizedBox(
        width: 400,
        child: OutlinedButton(
          onPressed: () async {
            await deleteDuplicates(selectedItemsCount);
          },
          child: Text("Delete $selectedItemsCount items"),
        ),
      ),
    );
  }

  void _selectAllGrids() {
    selectedGrids.clear();
    for (int idx = 0; idx < _duplicateCodes.length; idx++) {
      selectedGrids.add(idx);
    }
  }

  void _removeAllGrids() {
    selectedGrids.clear();
  }

  Future<void> deleteDuplicates(int itemCount) async {
    bool isAuthSuccessful = await LocalAuthenticationService.instance
        .requestLocalAuthentication(
          context,
          context.l10n.deleteCodeAuthMessage,
        );
    if (!isAuthSuccessful) {
      return;
    }
    if (!mounted) return;
    FocusScope.of(context).requestFocus();
    final l10n = context.l10n;
    final String message = "Are you sure you want to trash $itemCount items?";
    if (!mounted) return;
    await showChoiceActionSheet(
      context,
      title: l10n.deleteDuplicates,
      body: message,
      firstButtonLabel: l10n.trash,
      isCritical: true,
      firstButtonOnTap: () async {
        try {
          if (!mounted) return;
          for (int idx = 0; idx < _duplicateCodes.length; idx++) {
            if (selectedGrids.contains(idx)) {
              final List<Code> codes = _duplicateCodes[idx].codes;
              for (int i = 1; i < codes.length; i++) {
                final display = codes[i].display;
                final Code code = codes[i].copyWith(
                  display: display.copyWith(trashed: true),
                );
                await CodeStore.instance.addCode(code);
              }
            }
          }
          if (!mounted) return;
          Navigator.of(context).pop();
        } catch (e) {
          _logger.severe('Failed to trash duplicate codes: ${e.toString()}');
          showGenericErrorDialog(context: context, error: e).ignore();
        }
      },
    );
  }
}
