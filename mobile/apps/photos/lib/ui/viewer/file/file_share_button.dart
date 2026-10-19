import "dart:async";
import "dart:io";

import "package:ente_components/ente_components.dart";
import "package:ente_strings/ente_strings.dart";
import "package:flutter/cupertino.dart";
import "package:flutter/material.dart";
import "package:hugeicons/hugeicons.dart";
import "package:photos/ui/sharing/share_components.dart";

enum _FileShareAction { file, link }

class FileShareButton extends StatefulWidget {
  const FileShareButton({
    required this.canSendLink,
    required this.onSendFile,
    required this.onSendLink,
    super.key,
  });

  final bool canSendLink;
  final FutureOr<void> Function() onSendFile;
  final FutureOr<void> Function() onSendLink;

  @override
  State<FileShareButton> createState() => _FileShareButtonState();
}

class _FileShareButtonState extends State<FileShareButton> {
  ModalRoute<_FileShareAction>? _route;
  bool _sharing = false;

  @override
  void dispose() {
    final route = _route;
    if (route != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (route.isActive) route.navigator?.removeRoute(route);
      });
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: context.strings.share,
      icon: Platform.isAndroid
          ? const HugeIcon(
              icon: HugeIcons.strokeRoundedShare08,
              color: Colors.white,
            )
          : const Icon(CupertinoIcons.share, color: Colors.white),
      onPressed: _share,
    );
  }

  Future<void> _share() async {
    if (_sharing) return;
    _sharing = true;
    final sendFile = widget.onSendFile;
    final sendLink = widget.onSendLink;
    try {
      if (!widget.canSendLink) {
        await sendFile();
        return;
      }

      final action = await showBottomSheetComponent<_FileShareAction>(
        context: context,
        builder: (sheetContext) {
          _route = ModalRoute.of<_FileShareAction>(sheetContext);
          return const _FileShareSheet();
        },
      );
      // UIKit sharing must wait until the sheet's overlay has been removed.
      await _route?.completed;
      _route = null;
      if (!mounted) return;
      switch (action) {
        case _FileShareAction.file:
          await sendFile();
        case _FileShareAction.link:
          await sendLink();
        case null:
          break;
      }
    } finally {
      _sharing = false;
    }
  }
}

class _FileShareSheet extends StatelessWidget {
  const _FileShareSheet();

  @override
  Widget build(BuildContext context) {
    void select(_FileShareAction action) {
      if (ModalRoute.of(context)?.isCurrent ?? false) {
        Navigator.of(context).pop(action);
      }
    }

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.95,
      ),
      child: BottomSheetComponent(
        key: const ValueKey("file-share-sheet"),
        title: context.strings.share,
        closeTooltip: context.strings.close,
        content: Flexible(
          child: SingleChildScrollView(
            child: ShareMenuGroup(
              items: [
                ShareMenuItem(
                  key: const ValueKey("file-share-file"),
                  title: context.strings.sendACopy,
                  subtitle: context.strings.sendFileToAnotherApp,
                  icon: Platform.isAndroid
                      ? HugeIcons.strokeRoundedShare08
                      : null,
                  leading: Platform.isAndroid
                      ? null
                      : Icon(
                          CupertinoIcons.share,
                          size: IconSizes.small,
                          color: context.componentColors.textLight,
                        ),
                  onTap: () => select(_FileShareAction.file),
                ),
                ShareMenuItem(
                  key: const ValueKey("file-share-link"),
                  title: context.strings.sendLink,
                  subtitle: context.strings.shareLinkToThisItem,
                  icon: HugeIcons.strokeRoundedLink02,
                  onTap: () => select(_FileShareAction.link),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
