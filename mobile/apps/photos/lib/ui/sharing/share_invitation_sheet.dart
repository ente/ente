import "package:ente_components/ente_components.dart";
import "package:ente_strings/ente_strings.dart";
import "package:flutter/material.dart";
import "package:photos/models/collection/collection.dart";
import "package:photos/utils/dialog_util.dart";

Future<Collection?> showShareInvitationSheet({
  required BuildContext context,
  required String inviterName,
  required String albumName,
  required List<int> Function() getAcceptanceIDs,
  required Future<Collection> Function(List<int>) onAccept,
  required Future<void> Function() onReject,
}) {
  return showBottomSheetComponent<Collection>(
    context: context,
    builder: (_) => _ShareInvitationSheet(
      inviterName: inviterName,
      albumName: albumName,
      getAcceptanceIDs: getAcceptanceIDs,
      onAccept: onAccept,
      onReject: onReject,
    ),
  );
}

class _ShareInvitationSheet extends StatefulWidget {
  const _ShareInvitationSheet({
    required this.inviterName,
    required this.albumName,
    required this.getAcceptanceIDs,
    required this.onAccept,
    required this.onReject,
  });

  final String inviterName;
  final String albumName;
  final List<int> Function() getAcceptanceIDs;
  final Future<Collection> Function(List<int>) onAccept;
  final Future<void> Function() onReject;

  @override
  State<_ShareInvitationSheet> createState() => _ShareInvitationSheetState();
}

class _ShareInvitationSheetState extends State<_ShareInvitationSheet> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    return BottomSheetComponent(
      title: strings.shareInviteTitle,
      closeTooltip: strings.close,
      content: Text(
        strings.shareInviteBody(
          inviter: widget.inviterName,
          album: widget.albumName,
        ),
        style: TextStyles.body.copyWith(
          color: context.componentColors.textLight,
        ),
      ),
      actions: [
        ButtonComponent(
          label: strings.shareInviteAccept,
          isDisabled: _busy,
          shouldShowSuccessState: false,
          onTap: _accept,
        ),
        ButtonComponent(
          label: strings.shareInviteReject,
          variant: ButtonComponentVariant.secondary,
          isDisabled: _busy,
          shouldShowSuccessState: false,
          onTap: _reject,
        ),
      ],
    );
  }

  Future<void> _accept() async {
    final collectionIDs = List<int>.of(widget.getAcceptanceIDs());
    setState(() => _busy = true);
    try {
      if (collectionIDs.length > 1) {
        final confirmed = await showBottomSheetComponent<bool>(
          context: context,
          builder: (sheetContext) => BottomSheetComponent(
            title: sheetContext.strings.shareInviteTitle,
            closeTooltip: sheetContext.strings.close,
            content: Text(
              sheetContext.strings.acceptOtherShareInvitesBody(
                inviter: widget.inviterName,
              ),
              style: TextStyles.body.copyWith(
                color: sheetContext.componentColors.textLight,
              ),
            ),
            actions: [
              ButtonComponent(
                label: sheetContext.strings.shareInviteAccept,
                shouldSurfaceExecutionStates: false,
                onTap: () => Navigator.of(sheetContext).pop(true),
              ),
              ButtonComponent(
                label: sheetContext.strings.cancel,
                variant: ButtonComponentVariant.secondary,
                shouldSurfaceExecutionStates: false,
                onTap: () => Navigator.of(sheetContext).pop(false),
              ),
            ],
          ),
        );
        if (confirmed != true || !mounted) return;
      }
      final collection = await widget.onAccept(collectionIDs);
      if (mounted) Navigator.of(context).pop(collection);
    } catch (error) {
      if (mounted) {
        await showGenericErrorBottomSheet(context: context, error: error);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reject() async {
    setState(() => _busy = true);
    try {
      await widget.onReject();
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) {
        await showGenericErrorBottomSheet(context: context, error: error);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
