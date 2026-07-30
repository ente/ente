import "dart:math" as math;

import "package:ente_components/ente_components.dart";
import "package:flutter/material.dart";
import "package:photos/generated/l10n.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/file_load_result.dart";
import "package:photos/models/selected_files.dart";
import "package:photos/services/search_service.dart";
import "package:photos/theme/colors.dart";
import "package:photos/ui/viewer/gallery/gallery.dart";
import "package:photos/ui/viewer/gallery/state/gallery_files_inherited_widget.dart";

sealed class ContactPhotoPickerResult {
  const ContactPhotoPickerResult();
}

class ContactPhotoPickerFile extends ContactPhotoPickerResult {
  const ContactPhotoPickerFile(this.file);

  final EnteFile file;
}

class ContactPhotoPickerRemove extends ContactPhotoPickerResult {
  const ContactPhotoPickerRemove();
}

Future<ContactPhotoPickerResult?> showContactPhotoPickerSheet(
  BuildContext context, {
  required bool canRemovePhoto,
}) {
  return showBottomSheetComponent<ContactPhotoPickerResult>(
    context: context,
    barrierColor: backdropFaintDark,
    enableDrag: true,
    builder: (context) =>
        _ContactPhotoPickerSheet(canRemovePhoto: canRemovePhoto),
  );
}

class _ContactPhotoPickerSheet extends StatefulWidget {
  const _ContactPhotoPickerSheet({required this.canRemovePhoto});

  final bool canRemovePhoto;

  @override
  State<_ContactPhotoPickerSheet> createState() =>
      _ContactPhotoPickerSheetState();
}

class _ContactPhotoPickerSheetState extends State<_ContactPhotoPickerSheet> {
  final _selectedFiles = SelectedFiles();

  @override
  void dispose() {
    _selectedFiles.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final screenHeight = MediaQuery.sizeOf(context).height;
    final sheetHeight = math.min(screenHeight * 0.78, screenHeight - 80);

    return SizedBox(
      height: sheetHeight,
      child: BottomSheetComponent(
        title: l10n.setAContactPhoto,
        content: Expanded(
          child: GalleryFilesState(
            child: Gallery(
              asyncLoader:
                  (creationStartTime, creationEndTime, {limit, asc}) async {
                    final files = await SearchService.instance
                        .getAllFilesForContactPhotoPicker();
                    return FileLoadResult(files, false);
                  },
              tagPrefix: "pick_contact_photo_gallery",
              selectedFiles: _selectedFiles,
              limitSelectionToOne: true,
              showSelectAll: false,
              disablePinnedGroupHeader: true,
              disableVerticalPaddingForScrollbar: true,
            ),
          ),
        ),
        actions: [
          ListenableBuilder(
            listenable: _selectedFiles,
            builder: (context, _) {
              final isFileSelected = _selectedFiles.files.isNotEmpty;
              return ButtonComponent(
                label: l10n.setSelectedPhoto,
                isDisabled: !isFileSelected,
                shouldSurfaceExecutionStates: false,
                onTap: isFileSelected
                    ? () {
                        Navigator.pop(
                          context,
                          ContactPhotoPickerFile(_selectedFiles.files.first),
                        );
                      }
                    : null,
              );
            },
          ),
          if (widget.canRemovePhoto)
            ButtonComponent(
              label: l10n.removeContactPhoto,
              variant: ButtonComponentVariant.secondary,
              shouldSurfaceExecutionStates: false,
              onTap: () {
                Navigator.pop(context, const ContactPhotoPickerRemove());
              },
            ),
        ],
      ),
    );
  }
}
