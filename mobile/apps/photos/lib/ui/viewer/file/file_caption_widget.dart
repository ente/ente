import 'package:flutter/material.dart';
import "package:photos/core/event_bus.dart";
import "package:photos/events/file_caption_updated_event.dart";
import "package:photos/generated/l10n.dart";
import 'package:photos/models/file/file.dart';
import 'package:photos/theme/ente_theme.dart';
import 'package:photos/ui/components/keyboard/keyboard_oveylay.dart';
import 'package:photos/ui/components/keyboard/keyboard_top_button.dart';
import "package:photos/ui/notification/toast.dart";
import 'package:photos/utils/magic_util.dart';

class FileCaptionReadyOnly extends StatelessWidget {
  final String caption;

  const FileCaptionReadyOnly({super.key, required this.caption});

  @override
  Widget build(BuildContext context) {
    final colorScheme = getEnteColorScheme(context);
    final textTheme = getEnteTextTheme(context);
    return Padding(
      padding: const EdgeInsets.all(4.0),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minHeight: 32.0,
          minWidth: double.infinity,
          maxHeight: 200.0,
          maxWidth: double.infinity,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colorScheme.fillFaint,
            borderRadius: BorderRadius.circular(4),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.vertical,
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Text(caption, style: textTheme.small),
            ),
          ),
        ),
      ),
    );
  }
}

class FileCaptionWidget extends StatefulWidget {
  final EnteFile file;

  const FileCaptionWidget({required this.file, super.key});

  @override
  State<FileCaptionWidget> createState() => _FileCaptionWidgetState();
}

class _FileCaptionWidgetState extends State<FileCaptionWidget> {
  static const int maxLength = 5000;

  // counterThreshold represents the nun of char after which
  // currentLength/maxLength will show up
  static const int counterThreshold = 1000;
  int currentLength = 0;

  final _textController = TextEditingController();
  final _focusNode = FocusNode();
  String? editedCaption;
  late String defaultHintText = AppLocalizations.of(
    context,
  ).fileInfoAddDescHint;
  String hintText = '';
  Widget? keyboardTopButtons;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_focusNodeListener);
    editedCaption = widget.file.caption;
    if (editedCaption != null && editedCaption!.isNotEmpty) {
      hintText = editedCaption!;
    }
  }

  @override
  void dispose() {
    if (editedCaption != null) {
      editFileCaption(
        null,
        widget.file,
        editedCaption!,
      ).then((isSuccess) => _onEditFileFinish(isSuccess));
    }
    _textController.dispose();
    _focusNode.removeListener(_focusNodeListener);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (hintText.isEmpty) {
      hintText = defaultHintText;
    }
    final colorScheme = getEnteColorScheme(context);
    final textTheme = getEnteTextTheme(context);
    return TextField(
      onSubmitted: (value) async {
        await _onDoneClick(context);
      },
      controller: _textController,
      focusNode: _focusNode,
      decoration: InputDecoration(
        counterStyle: textTheme.mini.copyWith(color: colorScheme.textMuted),
        counterText: currentLength >= counterThreshold
            ? currentLength.toString() + " / " + maxLength.toString()
            : "",
        contentPadding: const EdgeInsets.all(16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(2),
          borderSide: const BorderSide(width: 0, style: BorderStyle.none),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(2),
          borderSide: const BorderSide(width: 0, style: BorderStyle.none),
        ),
        filled: true,
        fillColor: colorScheme.fillFaint,
        hintText: hintText,
        hintStyle: hintText == defaultHintText
            ? textTheme.miniMuted
            : textTheme.mini,
      ),
      style: textTheme.mini,
      cursorWidth: 1.5,
      maxLength: maxLength,
      minLines: 1,
      maxLines: 10,
      textCapitalization: TextCapitalization.sentences,
      keyboardType: TextInputType.multiline,
      onChanged: (value) {
        setState(() {
          hintText = defaultHintText;
          currentLength = value.length;
          editedCaption = value;
        });
      },
    );
  }

  Future<void> _onDoneClick(BuildContext context) async {
    if (editedCaption != null) {
      final isSuccesful = await editFileCaption(
        context,
        widget.file,
        editedCaption!,
      ).then((isSuccess) => _onEditFileFinish(isSuccess));
      if (isSuccesful) {
        if (mounted) {
          if (!context.mounted) return;
          Navigator.pop(context);
        }
      }
    }
  }

  void onCancelTap() {
    _textController.text = widget.file.caption ?? '';
    _focusNode.unfocus();
    editedCaption = null;
  }

  void onDoneTap() {
    _focusNode.unfocus();
    _onDoneClick(context);
  }

  void _focusNodeListener() {
    final caption = widget.file.caption;
    if (_focusNode.hasFocus && caption != null) {
      _textController.text = caption;
      editedCaption = caption;
    }
    final bool hasFocus = _focusNode.hasFocus;
    keyboardTopButtons ??= KeyboardTopButton(
      onDoneTap: onDoneTap,
      onCancelTap: onCancelTap,
    );
    if (hasFocus) {
      KeyboardOverlay.showOverlay(context, keyboardTopButtons!);
    } else {
      KeyboardOverlay.removeOverlay();
    }
  }

  bool _onEditFileFinish(bool isSuccess) {
    if (!mounted) {
      return isSuccess;
    }
    if (isSuccess) {
      widget.file.pubMagicMetadata?.caption = editedCaption;
      final generatedID = widget.file.generatedID;
      if (generatedID != null) {
        Bus.instance.fire(FileCaptionUpdatedEvent(generatedID));
      }
      return true;
    } else {
      showShortToast(context, AppLocalizations.of(context).somethingWentWrong);
      return false;
    }
  }
}
