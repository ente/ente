import "package:ente_auth/l10n/l10n.dart";
import 'package:ente_auth/store/code_display_store.dart';
import 'package:ente_auth/utils/dialog_util.dart';
import 'package:flutter/material.dart';

class EditTagDialog extends StatefulWidget {
  const EditTagDialog({super.key, required this.tag});

  final String tag;

  @override
  State<EditTagDialog> createState() => _EditTagDialogState();
}

class _EditTagDialogState extends State<EditTagDialog> {
  late String _tag = widget.tag;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(l10n.editTag),
      content: SingleChildScrollView(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextFormField(
              maxLength: 100,
              decoration: InputDecoration(
                hintText: l10n.tag,
                hintStyle: const TextStyle(color: Colors.white30),
                contentPadding: const EdgeInsets.all(12),
              ),
              onChanged: (value) {
                setState(() {
                  _tag = value;
                });
              },
              autocorrect: false,
              initialValue: _tag,
              autofocus: true,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          child: Text(
            l10n.cancel,
            style: const TextStyle(color: Colors.redAccent),
          ),
          onPressed: () {
            Navigator.pop(context);
          },
        ),
        TextButton(
          child: Text(
            l10n.saveAction,
            style: const TextStyle(color: Colors.purple),
          ),
          onPressed: () async {
            if (_tag.trim().isEmpty) return;

            final dialog = createProgressDialog(
              context,
              context.l10n.pleaseWait,
            );
            await dialog.show();

            await CodeDisplayStore.instance.editTag(widget.tag, _tag);

            await dialog.hide();

            if (!context.mounted) return;
            Navigator.pop(context);
          },
        ),
      ],
    );
  }
}
