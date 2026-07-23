import 'dart:ui';

import 'package:ente_auth/l10n/l10n.dart';
import 'package:ente_auth/models/code.dart';
import 'package:ente_auth/services/preference_service.dart';
import 'package:ente_auth/store/code_store.dart';
import 'package:ente_auth/ui/code_widget.dart';
import 'package:ente_components/ente_components.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';

class ReorderCodesPage extends StatefulWidget {
  const ReorderCodesPage({super.key, required this.codes});

  final List<Code> codes;

  @override
  State<ReorderCodesPage> createState() => _ReorderCodesPageState();
}

class _ReorderCodesPageState extends State<ReorderCodesPage> {
  final logger = Logger('ReorderCodesPage');
  final ScrollController _scrollController = ScrollController();
  bool hasChanged = false;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    final isCompactMode = PreferenceService.instance.isCompactMode();

    return Semantics(
      container: true,
      identifier: 'auth_reorder_codes_page',
      child: Scaffold(
        backgroundColor: colors.backgroundBase,
        body: Scrollbar(
          controller: _scrollController,
          thumbVisibility: true,
          interactive: true,
          child: AppBarComponent(
            title: context.l10n.customOrder,
            controller: _scrollController,
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: Spacing.sm),
                child: Semantics(
                  button: true,
                  identifier: 'auth_reorder_save',
                  child: IconButtonComponent(
                    icon: const Icon(
                      Icons.check_rounded,
                      size: IconSizes.medium,
                    ),
                    variant: IconButtonComponentVariant.unfilled,
                    tooltip: context.l10n.save,
                    onTap: hasChanged ? _save : null,
                  ),
                ),
              ),
            ],
            slivers: [
              SliverSafeArea(
                top: false,
                sliver: SliverReorderableList(
                  itemCount: widget.codes.length,
                  proxyDecorator: _proxyDecorator,
                  itemBuilder: (context, index) {
                    final code = widget.codes[index];
                    return _ReorderableCodeRow(
                      key: ValueKey('${code.hashCode}_${code.generatedID}'),
                      code: code,
                      index: index,
                      isCompactMode: isCompactMode,
                    );
                  },
                  onReorder: updateCodeIndex,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _proxyDecorator(Widget child, int index, Animation<double> animation) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final scale = lerpDouble(
          1,
          1.03,
          Curves.easeInOut.transform(animation.value),
        )!;
        return Transform.scale(scale: scale, child: child);
      },
    );
  }

  Future<void> _save() async {
    if (!hasChanged) return;
    final hasSaved = await saveUpdatedIndexes();
    if (hasSaved && mounted) Navigator.of(context).pop();
  }

  Future<bool> saveUpdatedIndexes() {
    return CodeStore.instance.saveUpadedIndexes(widget.codes);
  }

  void updateCodeIndex(int oldIndex, int newIndex) {
    setState(() {
      if (oldIndex < newIndex) newIndex -= 1;
      final code = widget.codes.removeAt(oldIndex);
      widget.codes.insert(newIndex, code);
      hasChanged = true;
    });
  }
}

class _ReorderableCodeRow extends StatelessWidget {
  const _ReorderableCodeRow({
    super.key,
    required this.code,
    required this.index,
    required this.isCompactMode,
  });

  final Code code;
  final int index;
  final bool isCompactMode;

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    return Row(
      children: [
        Expanded(
          child: CodeWidget(
            key: ValueKey(code.generatedID),
            code,
            isCompactMode: isCompactMode,
            isReordering: true,
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(right: Spacing.lg),
          child: ReorderableDragStartListener(
            index: index,
            child: Semantics(
              button: true,
              label: '${code.issuer}, ${code.account}',
              identifier: 'auth_reorder_handle',
              child: Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: colors.fillLight,
                  borderRadius: BorderRadius.circular(Radii.button),
                ),
                child: Icon(
                  Icons.drag_handle_rounded,
                  size: IconSizes.medium,
                  color: colors.textLight,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
