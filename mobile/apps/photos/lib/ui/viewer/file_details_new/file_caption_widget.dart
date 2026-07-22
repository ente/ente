import "package:ente_components/ente_components.dart";
import "package:flutter/material.dart";
import "package:hugeicons/hugeicons.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/events/file_caption_updated_event.dart";
import "package:photos/generated/l10n.dart";
import "package:photos/models/file/file.dart";
import "package:photos/ui/notification/toast.dart";
import "package:photos/utils/magic_util.dart";

class FileCaptionWidgetNew extends StatefulWidget {
  const FileCaptionWidgetNew({required this.file, super.key});

  final EnteFile file;

  @override
  State<FileCaptionWidgetNew> createState() => _FileCaptionWidgetNewState();
}

class _FileCaptionWidgetNewState extends State<FileCaptionWidgetNew> {
  static const int maxLength = 5000;

  final _textController = TextEditingController();
  final _focusNode = FocusNode();
  late String _editedCaption;
  Future<bool>? _saveInFlight;

  @override
  void initState() {
    super.initState();
    _editedCaption = widget.file.caption ?? "";
    _textController.text = _editedCaption;
  }

  @override
  void dispose() {
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: TextInputComponent(
            controller: _textController,
            focusNode: _focusNode,
            hintText: AppLocalizations.of(context).fileInfoAddDescHint,
            maxLength: maxLength,
            minLines: 1,
            maxLines: 10,
            textCapitalization: TextCapitalization.sentences,
            keyboardType: TextInputType.multiline,
            onChanged: (value) {
              if (_editedCaption == value) return;
              setState(() => _editedCaption = value);
            },
          ),
        ),
        const SizedBox(width: Spacing.sm),
        IconButtonComponent(
          variant: IconButtonComponentVariant.green,
          tooltip: AppLocalizations.of(context).done,
          icon: const HugeIcon(icon: HugeIcons.strokeRoundedTick02),
          onTap: _hasPendingEdit ? _saveInteractive : null,
        ),
      ],
    );
  }

  bool get _hasPendingEdit => _editedCaption != (widget.file.caption ?? "");

  Future<void> _saveInteractive() async {
    _focusNode.unfocus();
    final success = await _persist(_editedCaption, context);
    if (mounted && success) setState(() {});
  }

  Future<bool> _persist(String caption, BuildContext? saveContext) async {
    final inFlight = _saveInFlight;
    if (inFlight != null) {
      await inFlight;
      return _persist(caption, null);
    }
    if (caption == (widget.file.caption ?? "")) return true;

    final save = editFileCaption(saveContext, widget.file, caption);
    _saveInFlight = save;
    final success = await save;
    if (identical(_saveInFlight, save)) _saveInFlight = null;

    if (success) {
      widget.file.pubMagicMetadata?.caption = caption;
      final generatedID = widget.file.generatedID;
      if (generatedID != null) {
        Bus.instance.fire(FileCaptionUpdatedEvent(generatedID));
      }
    } else if (saveContext != null && saveContext.mounted) {
      showShortToast(
        saveContext,
        AppLocalizations.of(saveContext).somethingWentWrong,
      );
    }
    return success;
  }
}
