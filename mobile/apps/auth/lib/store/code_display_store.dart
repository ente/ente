import 'package:ente_auth/l10n/l10n.dart';
import 'package:ente_auth/models/code.dart';
import 'package:ente_auth/services/authenticator_service.dart';
import 'package:ente_auth/store/code_store.dart';
import 'package:ente_auth/utils/dialog_util.dart';
import 'package:flutter/material.dart';

class CodeDisplayStore {
  static final CodeDisplayStore instance =
      CodeDisplayStore._privateConstructor();

  CodeDisplayStore._privateConstructor();

  late CodeStore _codeStore;

  final ValueNotifier<bool> isSelectionModeActive = ValueNotifier(false);
  final ValueNotifier<Set<String>> selectedCodeIds = ValueNotifier(<String>{});

  // toggles the selection status of a code
  void toggleSelection(String codeId) {
    final newSelection = Set<String>.from(selectedCodeIds.value);

    if (newSelection.contains(codeId)) {
      newSelection.remove(codeId);
    } else {
      newSelection.add(codeId);
    }

    selectedCodeIds.value =
        newSelection; //if we selected atleast one code, then we're in selection mode.. else: exit selection mode
    isSelectionModeActive.value = newSelection.isNotEmpty;
  }

  //method to clear the entire selection
  void clearSelection() {
    selectedCodeIds.value = <String>{};
    isSelectionModeActive.value = false;
  }

  /// Reconciles current selections with the provided list of codes.
  ///
  /// This ensures selection state remains valid when:
  /// - Codes transition from local to synced (rawData → generatedID)
  /// - Codes are deleted or removed from the list
  /// - Codes are marked with errors and become invalid for selection
  ///
  /// **How it works:**
  /// 1. Builds a set of valid selection keys from non-error codes
  /// 2. Creates a remapping table for old keys (rawData, old generatedID) → new keys
  /// 3. Updates current selection by keeping valid keys and remapping changed keys
  /// 4. Removes selections for codes that no longer exist or have errors
  ///
  /// **Performance:** O(n + m) where n = number of codes, m = number of selected items
  ///
  /// **Example scenario:**
  /// ```dart
  /// // User selects code with rawData="abc123" (not yet synced)
  /// selectedCodeIds = {"abc123"}
  ///
  /// // After sync, code gets generatedID=42
  /// // reconcileSelections maps "abc123" → "42"
  /// selectedCodeIds = {"42"}  // Selection preserved!
  /// ```
  void reconcileSelections(Iterable<Code> codes) {
    final currentSelection = selectedCodeIds.value;
    if (currentSelection.isEmpty) {
      return;
    }

    // Build lookup structures in a single pass - O(n)
    final validKeys = <String>{};
    final keyRemapping = <String, String>{};

    for (final code in codes) {
      if (code.hasError) {
        continue;
      }

      final key = code.selectionKey;
      validKeys.add(key);

      // Map old keys to current key to handle transitions
      keyRemapping[code.rawData] = key;
      final generatedID = code.generatedID;
      if (generatedID != null) {
        keyRemapping[generatedID.toString()] = key;
      }
    }

    // Update selection in one pass - O(m)
    final updatedSelection = currentSelection
        .map(
          (oldKey) =>
              validKeys.contains(oldKey) ? oldKey : keyRemapping[oldKey],
        )
        .whereType<String>()
        .toSet();

    // Only update if selection changed
    if (updatedSelection != currentSelection) {
      selectedCodeIds.value = updatedSelection;
      isSelectionModeActive.value = updatedSelection.isNotEmpty;
    }
  }

  Future<void> init() async {
    _codeStore = CodeStore.instance;
  }

  Future<List<String>> getAllTags({
    AccountMode? accountMode,
    List<Code>? allCodes,
  }) async {
    final codes =
        allCodes ??
        await _codeStore.getAllCodes(
          accountMode: accountMode,
          sortCodes: false,
        );
    final tags = <String>{};
    for (final code in codes) {
      if (code.hasError) continue;
      if (code.isTrashed) continue;
      tags.addAll(code.display.tags);
    }
    return tags.toList()..sort();
  }

  Future<void> showDeleteTagDialog(BuildContext context, String tag) async {
    FocusScope.of(context).requestFocus();
    final l10n = context.l10n;

    await showChoiceActionSheet(
      context,
      title: l10n.deleteTagTitle,
      body: l10n.deleteTagMessage,
      firstButtonLabel: l10n.delete,
      isCritical: true,
      firstButtonOnTap: () async {
        // traverse through all the codes and edit this tag's value
        final relevantCodes = await _getCodesByTag(tag);

        final tasks = <Future<AddResult>>[];

        for (final code in relevantCodes) {
          final tags = code.display.tags;
          tags.remove(tag);
          tasks.add(
            _codeStore.addCode(
              code.copyWith(display: code.display.copyWith(tags: tags)),
              shouldSync: false,
            ),
          );
        }

        final results = await Future.wait(tasks);
        if (results.any((r) => r != AddResult.duplicate) &&
            AuthenticatorService.instance.getAccountMode() ==
                AccountMode.online) {
          AuthenticatorService.instance.onlineSync().ignore();
        }
      },
    );
  }

  Future<void> showEditDialog(BuildContext context, String tag) async {
    await showTextInputDialog(
      context,
      title: context.l10n.editTag,
      label: context.l10n.tag,
      initialValue: tag,
      submitButtonLabel: context.l10n.saveAction,
      maxLength: 100,
      onSubmit: (value) async {
        final updatedTag = value.trim();
        if (updatedTag.isEmpty || updatedTag == tag) return;
        await editTag(tag, updatedTag);
      },
    );
  }

  Future<List<Code>> _getCodesByTag(String tag) async {
    final codes = await _codeStore.getAllCodes(sortCodes: false);
    return codes
        .where(
          (element) => !element.hasError && element.display.tags.contains(tag),
        )
        .toList();
  }

  Future<void> editTag(String previousTag, String updatedTag) async {
    // traverse through all the codes and edit this tag's value
    final relevantCodes = await _getCodesByTag(previousTag);

    final tasks = <Future<AddResult>>[];

    for (final code in relevantCodes) {
      final tags = code.display.tags;
      tags.remove(previousTag);
      tags.add(updatedTag);
      tasks.add(
        CodeStore.instance.addCode(
          code.copyWith(display: code.display.copyWith(tags: tags)),
          shouldSync: false,
        ),
      );
    }

    final results = await Future.wait(tasks);
    if (results.any((r) => r != AddResult.duplicate) &&
        AuthenticatorService.instance.getAccountMode() == AccountMode.online) {
      AuthenticatorService.instance.onlineSync().ignore();
    }
  }
}
