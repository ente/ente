import "package:ente_components/ente_components.dart";
import "package:ente_ui/components/buttons/button_widget.dart";
import "package:ente_ui/components/buttons/models/button_result.dart";
import "package:flutter/material.dart";
import "package:locker/l10n/l10n.dart";

class DeleteConfirmationResult {
  final ButtonResult buttonResult;
  final bool deleteFromAllCollections;

  DeleteConfirmationResult({
    required this.buttonResult,
    required this.deleteFromAllCollections,
  });
}

Future<DeleteConfirmationResult?> showDeleteConfirmationSheet(
  BuildContext context, {
  required String title,
  required String body,
  required String deleteButtonLabel,
  required Widget illustration,
  bool showDeleteFromAllCollectionsOption = false,
}) {
  return showBottomSheetComponent<DeleteConfirmationResult>(
    context: context,
    builder: (_) => DeleteConfirmationSheet(
      title: title,
      body: body,
      deleteButtonLabel: deleteButtonLabel,
      illustration: illustration,
      showDeleteFromAllCollectionsOption: showDeleteFromAllCollectionsOption,
    ),
  );
}

class DeleteConfirmationSheet extends StatefulWidget {
  final String title;
  final String body;
  final String deleteButtonLabel;
  final Widget illustration;
  final bool showDeleteFromAllCollectionsOption;

  const DeleteConfirmationSheet({
    super.key,
    required this.title,
    required this.body,
    required this.deleteButtonLabel,
    required this.illustration,
    required this.showDeleteFromAllCollectionsOption,
  });

  @override
  State<DeleteConfirmationSheet> createState() =>
      _DeleteConfirmationSheetState();
}

class _DeleteConfirmationSheetState extends State<DeleteConfirmationSheet> {
  bool _deleteFromAllCollections = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;

    return BottomSheetComponent(
      illustration: widget.illustration,
      title: widget.title,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            widget.body,
            style: TextStyles.body.copyWith(color: colors.textLight),
            textAlign: TextAlign.center,
          ),
          if (widget.showDeleteFromAllCollectionsOption) ...[
            const SizedBox(height: 20),
            Center(
              child: LabeledControlComponent(
                control: CheckboxComponent(
                  selected: _deleteFromAllCollections,
                  onChanged: (value) {
                    setState(() {
                      _deleteFromAllCollections = value;
                    });
                  },
                ),
                label: context.l10n.deleteCollectionFromEverywhere,
                onTap: () {
                  setState(() {
                    _deleteFromAllCollections = !_deleteFromAllCollections;
                  });
                },
              ),
            ),
          ],
        ],
      ),
      actions: [
        ButtonComponent(
          label: widget.deleteButtonLabel,
          variant: ButtonComponentVariant.critical,
          onTap: () {
            Navigator.of(context).pop(
              DeleteConfirmationResult(
                buttonResult: ButtonResult(ButtonAction.first),
                deleteFromAllCollections: _deleteFromAllCollections,
              ),
            );
          },
        ),
      ],
    );
  }
}
