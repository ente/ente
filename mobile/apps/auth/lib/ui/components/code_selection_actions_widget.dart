import "package:ente_auth/l10n/l10n.dart";
import "package:ente_auth/models/code.dart";
import "package:ente_auth/ui/components/selection_action_button.dart";
import 'package:flutter/material.dart';

class CodeSelectionActionsWidget extends StatefulWidget {
  final Code code;
  final bool showPin;
  final VoidCallback? onShare;
  final VoidCallback? onPin;
  final VoidCallback? onShowQR;
  final VoidCallback? onEdit;
  final VoidCallback? onRestore;
  final VoidCallback? onDelete;
  final VoidCallback? onTrashed;

  const CodeSelectionActionsWidget({
    super.key,
    required this.code,
    this.showPin = true,
    this.onShare,
    this.onPin,
    this.onShowQR,
    this.onEdit,
    this.onRestore,
    this.onDelete,
    this.onTrashed,
  });

  @override
  State<CodeSelectionActionsWidget> createState() =>
      _CodeSelectionActionsWidgetState();
}

class _CodeSelectionActionsWidgetState
    extends State<CodeSelectionActionsWidget> {
  late final scrollController = ScrollController();

  // static final _logger = Logger("CodeSelectionActionsWidget");

  @override
  void dispose() {
    scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final List<SelectionActionButton> items = [];

    if (!widget.code.isTrashed) {
      items.add(
        SelectionActionButton(
          labelText: context.l10n.share,
          icon: Icons.adaptive.share_outlined,
          onTap: widget.onShare,
        ),
      );
      if (widget.showPin) {
        items.add(
          SelectionActionButton(
            labelText: widget.code.isPinned
                ? context.l10n.unpinText
                : context.l10n.pinText,
            icon: widget.code.isPinned
                ? Icons.push_pin
                : Icons.push_pin_outlined,
            onTap: widget.onPin,
          ),
        );
      }

      items.add(
        SelectionActionButton(
          labelText: 'QR',
          icon: Icons.qr_code_2_outlined,
          onTap: widget.onShowQR,
        ),
      );
    }

    if (widget.code.isTrashed) {
      items.add(
        SelectionActionButton(
          labelText: context.l10n.restore,
          icon: Icons.restore_outlined,
          onTap: widget.onRestore,
        ),
      );
    } else {
      items.add(
        SelectionActionButton(
          labelText: context.l10n.edit,
          icon: Icons.edit,
          onTap: widget.onEdit,
        ),
      );
    }

    items.add(
      SelectionActionButton(
        labelText: widget.code.isTrashed
            ? context.l10n.delete
            : context.l10n.trash,
        icon: widget.code.isTrashed ? Icons.delete_forever : Icons.delete,
        onTap: widget.code.isTrashed ? widget.onDelete : widget.onTrashed,
      ),
    );

    if (items.isNotEmpty) {
      // h4ck: https://github.com/flutter/flutter/issues/57920#issuecomment-893970066
      return MediaQuery(
        data: MediaQuery.of(context).removePadding(removeBottom: true),
        child: SafeArea(
          child: Scrollbar(
            radius: const Radius.circular(1),
            thickness: 2,
            controller: scrollController,
            thumbVisibility: true,
            child: SingleChildScrollView(
              controller: scrollController,
              physics: const BouncingScrollPhysics(
                decelerationRate: ScrollDecelerationRate.fast,
              ),
              scrollDirection: Axis.horizontal,
              child: Container(
                padding: const EdgeInsets.only(bottom: 24),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(width: 4),
                    ...items,
                    const SizedBox(width: 4),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }
    return const SizedBox();
  }
}
