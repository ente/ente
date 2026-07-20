import 'dart:async';

import 'package:ente_auth/l10n/l10n.dart';
import 'package:ente_auth/models/code.dart';
import 'package:ente_auth/onboarding/model/tag_enums.dart';
import 'package:ente_auth/onboarding/view/common/tag_chip.dart';
import 'package:ente_auth/services/authenticator_service.dart';
import 'package:ente_auth/store/code_display_store.dart';
import 'package:ente_auth/store/code_store.dart';
import 'package:ente_auth/ui/components/horizontal_scroll_area.dart';
import 'package:ente_auth/ui/utils/icon_utils.dart';
import 'package:ente_auth/utils/dialog_util.dart';
import 'package:ente_components/ente_components.dart';
import 'package:flutter/material.dart';

class AddTagSheet extends StatefulWidget {
  final List<Code> selectedCodes;

  const AddTagSheet({super.key, required this.selectedCodes});

  @override
  State<AddTagSheet> createState() => _AddTagSheetState();
}

class _AddTagSheetState extends State<AddTagSheet> {
  List<String> _allTags = [];
  final Set<String> _selectedTagsInSheet = {};
  final Set<String> _initialIntersectionTags = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadInitialState();
  }

  Future<void> _loadInitialState() async {
    final allTagsFromServer = await CodeDisplayStore.instance.getAllTags();

    // Calculate intersection: tags that exist in ALL selected codes
    final initialTagsForSelection = widget.selectedCodes.isEmpty
        ? <String>{}
        : widget.selectedCodes
              .map((code) => code.display.tags.toSet())
              .reduce((a, b) => a.intersection(b));

    if (mounted) {
      setState(() {
        _allTags = allTagsFromServer;
        _selectedTagsInSheet.addAll(initialTagsForSelection);
        _initialIntersectionTags.addAll(initialTagsForSelection);
        _isLoading = false;
      });
    }
  }

  Future<void> _onDonePressed() async {
    final removedTags = _initialIntersectionTags.difference(
      _selectedTagsInSheet,
    );
    final addedTags = _selectedTagsInSheet.difference(_initialIntersectionTags);

    final updateFutures = widget.selectedCodes.map((code) {
      final updatedTags = Set<String>.from(code.display.tags)
        ..removeAll(removedTags)
        ..addAll(addedTags);

      return CodeStore.instance.addCode(
        code.copyWith(
          display: code.display.copyWith(tags: updatedTags.toList()),
        ),
        shouldSync: false,
      );
    });

    final updateResults = await Future.wait(updateFutures);
    final hasChanges = updateResults.any((r) => r != AddResult.duplicate);
    if (hasChanges &&
        AuthenticatorService.instance.getAccountMode() == AccountMode.online) {
      AuthenticatorService.instance.onlineSync().ignore();
    }
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _showCreateTagDialog() async {
    String? newTag;
    await showTextInputDialog(
      context,
      title: context.l10n.createNewTag,
      submitButtonLabel: context.l10n.create,
      useRootNavigator: true,
      onSubmit: (value) async => newTag = value.trim(),
    );

    if (newTag?.isNotEmpty == true) {
      setState(() {
        if (!_allTags.contains(newTag!)) {
          _allTags.add(newTag!);
          _allTags.sort();
        }
        _selectedTagsInSheet.add(newTag!);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;

    return Semantics(
      identifier: 'auth_add_tag_sheet',
      child: BottomSheetComponent(
        title: '${widget.selectedCodes.length} ${context.l10n.selected}',
        closeTooltip: context.l10n.close,
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 80,
              child: HorizontalScrollArea(
                builder: (context, scrollController) => ListView.separated(
                  controller: scrollController,
                  scrollDirection: Axis.horizontal,
                  itemCount: widget.selectedCodes.length,
                  separatorBuilder: (_, _) => const SizedBox(width: Spacing.lg),
                  itemBuilder: (context, index) {
                    final code = widget.selectedCodes[index];
                    final iconData = code.display.isCustomIcon
                        ? code.display.iconID
                        : code.issuer;

                    return SizedBox(
                      width: 60,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 50,
                            height: 50,
                            decoration: BoxDecoration(
                              color: colors.fillLight,
                              borderRadius: BorderRadius.circular(Radii.md),
                            ),
                            child: Center(
                              child: IconUtils.instance.getIcon(
                                context,
                                iconData.trim(),
                                width: 28,
                              ),
                            ),
                          ),
                          const SizedBox(height: Spacing.sm),
                          Text(
                            code.issuer,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyles.mini.copyWith(
                              color: colors.textLight,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: Spacing.xl),
            Text(
              context.l10n.tags,
              style: TextStyles.bodyBold.copyWith(color: colors.textBase),
            ),
            const SizedBox(height: Spacing.md),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.25,
              ),
              child: SingleChildScrollView(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : Wrap(
                        spacing: Spacing.sm,
                        runSpacing: Spacing.sm,
                        children: [
                          ..._allTags.map((tag) {
                            final isSelected = _selectedTagsInSheet.contains(
                              tag,
                            );
                            return TagChip(
                              label: tag,
                              action: TagChipAction.check,
                              state: isSelected
                                  ? TagChipState.selected
                                  : TagChipState.unselected,
                              onTap: () {
                                setState(() {
                                  if (isSelected) {
                                    _selectedTagsInSheet.remove(tag);
                                  } else {
                                    _selectedTagsInSheet.add(tag);
                                  }
                                });
                              },
                            );
                          }),
                          TagChip(
                            label: context.l10n.addNew,
                            iconData: Icons.add,
                            state: TagChipState.unselected,
                            onTap: _showCreateTagDialog,
                          ),
                        ],
                      ),
              ),
            ),
          ],
        ),
        actions: [
          ButtonComponent(label: context.l10n.done, onTap: _onDonePressed),
        ],
      ),
    );
  }
}
