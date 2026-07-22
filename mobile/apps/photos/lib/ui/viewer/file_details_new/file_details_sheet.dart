import "dart:async";

import "package:ente_components/ente_components.dart";
import "package:flutter/material.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/events/details_sheet_event.dart";
import "package:photos/models/file/extensions/file_props.dart";
import "package:photos/models/file/file.dart";
import "package:photos/module/metadata/panorama.dart";
import "package:photos/ui/viewer/file/file_details_new_widget.dart";

Future<void> showFileDetailsNewSheet(
  BuildContext context,
  EnteFile file,
) async {
  if (file.canEditMetaInfo && file.isPanorama() == null) {
    guardedCheckPanorama(file).ignore();
  }
  Bus.instance.fire(
    DetailsSheetEvent(
      localID: file.localID,
      uploadedFileID: file.uploadedFileID,
      opened: true,
    ),
  );
  try {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => FileDetailsNewSheet(file: file),
    );
  } finally {
    Bus.instance.fire(
      DetailsSheetEvent(
        localID: file.localID,
        uploadedFileID: file.uploadedFileID,
        opened: false,
      ),
    );
  }
}

class FileDetailsNewSheet extends StatelessWidget {
  const FileDetailsNewSheet({required this.file, super.key});

  final EnteFile file;

  @override
  Widget build(BuildContext context) {
    final isKeyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 60;
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      snap: !isKeyboardOpen,
      snapSizes: isKeyboardOpen ? null : const [0.75],
      expand: false,
      builder: (context, scrollController) => Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: context.componentColors.backgroundBase,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(Radii.bottomSheet),
          ),
        ),
        child: FileDetailsNewWidget(file, scrollController: scrollController),
      ),
    );
  }
}
