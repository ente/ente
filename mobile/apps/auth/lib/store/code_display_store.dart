import 'package:ente_auth/models/code.dart';
import 'package:ente_auth/services/authenticator_service.dart';
import 'package:ente_auth/store/code_store.dart';
import 'package:ente_auth/utils/dialog_util.dart';
import 'package:ente_strings/ente_strings.dart';
import 'package:flutter/material.dart';

class CodeDisplayStore {
  static final CodeDisplayStore instance =
      CodeDisplayStore._privateConstructor();

  CodeDisplayStore._privateConstructor();

  late CodeStore _codeStore;

  final ValueNotifier<bool> isSelectionModeActive = ValueNotifier(false);
  final ValueNotifier<Set<String>> selectedCodeIds = ValueNotifier(<String>{});

  void toggleSelection(String codeId) {
    final newSelection = Set<String>.from(selectedCodeIds.value);

    if (newSelection.contains(codeId)) {
      newSelection.remove(codeId);
    } else {
      newSelection.add(codeId);
    }

    selectedCodeIds.value = newSelection;
    isSelectionModeActive.value = newSelection.isNotEmpty;
  }

  void clearSelection() {
    selectedCodeIds.value = <String>{};
    isSelectionModeActive.value = false;
  }

  // Preserve selections when rawData keys are replaced by generated IDs.
  void reconcileSelections(Iterable<Code> codes) {
    final currentSelection = selectedCodeIds.value;
    if (currentSelection.isEmpty) {
      return;
    }

    final validKeys = <String>{};
    final keyRemapping = <String, String>{};

    for (final code in codes) {
      if (code.hasError) {
        continue;
      }

      final key = code.selectionKey;
      validKeys.add(key);

      keyRemapping[code.rawData] = key;
      final generatedID = code.generatedID;
      if (generatedID != null) {
        keyRemapping[generatedID.toString()] = key;
      }
    }

    final updatedSelection = currentSelection
        .map(
          (oldKey) =>
              validKeys.contains(oldKey) ? oldKey : keyRemapping[oldKey],
        )
        .whereType<String>()
        .toSet();

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
    final l10n = context.strings;

    await showChoiceActionSheet(
      context,
      title: l10n.deleteTagTitle,
      body: l10n.deleteTagMessage,
      firstButtonLabel: l10n.delete,
      isCritical: true,
      firstButtonOnTap: () async {
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
      title: context.strings.editTag,
      label: context.strings.tag,
      initialValue: tag,
      submitButtonLabel: context.strings.save,
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
