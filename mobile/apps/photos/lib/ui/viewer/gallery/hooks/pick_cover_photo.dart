import "package:flutter/material.dart";
import "package:modal_bottom_sheet/modal_bottom_sheet.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/db/files_db.dart";
import "package:photos/events/collection_updated_event.dart";
import "package:photos/generated/l10n.dart";
import 'package:photos/models/collection/collection.dart';
import "package:photos/models/file_load_result.dart";
import "package:photos/models/selected_files.dart";
import "package:photos/services/ignored_files_service.dart";
import "package:photos/theme/colors.dart";
import "package:photos/theme/ente_theme.dart";
import "package:photos/ui/components/bottom_of_title_bar_widget.dart";
import "package:photos/ui/components/buttons/button_widget.dart";
import "package:photos/ui/components/models/button_type.dart";
import "package:photos/ui/components/title_bar_title_widget.dart";
import "package:photos/ui/viewer/gallery/gallery.dart";
import "package:photos/ui/viewer/gallery/state/gallery_files_inherited_widget.dart";

Future<int?> showPickCoverPhotoSheet(
  BuildContext context,
  Collection collection,
) async {
  return await showBarModalBottomSheet(
    context: context,
    builder: (context) {
      return PickCoverPhotoWidget(collection);
    },
    shape: const RoundedRectangleBorder(
      side: BorderSide(width: 0),
      borderRadius: BorderRadius.vertical(top: Radius.circular(5)),
    ),
    topControl: const SizedBox.shrink(),
    backgroundColor: getEnteColorScheme(context).backgroundElevated,
    barrierColor: backdropFaintDark,
    enableDrag: true,
  );
}

class PickCoverPhotoWidget extends StatelessWidget {
  final Collection collection;

  const PickCoverPhotoWidget(this.collection, {super.key});

  @override
  Widget build(BuildContext context) {
    final ValueNotifier<bool> isFileSelected = ValueNotifier(false);
    final selectedFiles = SelectedFiles();
    selectedFiles.addListener(() {
      isFileSelected.value = selectedFiles.files.isNotEmpty;
    });

    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 32, 0, 8),
      child: SizedBox(
        width: double.infinity,
        child: Column(
          mainAxisSize: MainAxisSize.max,
          children: [
            Expanded(
              child: Column(
                children: [
                  BottomOfTitleBarWidget(
                    title: TitleBarTitleWidget(
                      title: AppLocalizations.of(context).selectCoverPhoto,
                    ),
                    caption: collection.displayName,
                    showCloseButton: true,
                  ),
                  Expanded(
                    child: GalleryFilesState(
                      child: Gallery(
                        asyncLoader:
                            (
                              creationStartTime,
                              creationEndTime, {
                              limit,
                              asc,
                            }) async {
                              final FileLoadResult result = await FilesDB
                                  .instance
                                  .getFilesInCollection(
                                    collection.id,
                                    creationStartTime,
                                    creationEndTime,
                                    limit: limit,
                                    asc: asc,
                                  );
                              // hide ignored files from home page UI
                              final ignoredIDs = await IgnoredFilesService
                                  .instance
                                  .idToIgnoreReasonMap;
                              result.files.removeWhere(
                                (f) =>
                                    f.uploadedFileID == null &&
                                    IgnoredFilesService.instance
                                        .shouldSkipUpload(ignoredIDs, f),
                              );
                              return result;
                            },
                        reloadEvent: Bus.instance
                            .on<CollectionUpdatedEvent>()
                            .where(
                              (event) => event.collectionID == collection.id,
                            ),
                        tagPrefix: "pick_cover_photo_gallery",
                        selectedFiles: selectedFiles,
                        limitSelectionToOne: true,
                        showSelectAll: false,
                        sortAsyncFn: () =>
                            collection.pubMagicMetadata.asc ?? false,
                        disablePinnedGroupHeader: true,
                        disableVerticalPaddingForScrollbar: true,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SafeArea(
              child: Container(
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(
                      color: getEnteColorScheme(context).strokeFaint,
                    ),
                  ),
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 428),
                    child: Padding(
                      //inner stroke of 1pt + 15 pts of top padding = 16 pts
                      padding: const EdgeInsets.fromLTRB(16, 15, 16, 8),
                      child: Column(
                        children: [
                          ValueListenableBuilder(
                            valueListenable: isFileSelected,
                            builder: (context, bool value, _) {
                              return AnimatedSwitcher(
                                duration: const Duration(milliseconds: 300),
                                switchInCurve: Curves.easeInOutExpo,
                                switchOutCurve: Curves.easeInOutExpo,
                                child: ButtonWidget(
                                  key: ValueKey(value),
                                  isDisabled: !value,
                                  buttonType: ButtonType.neutral,
                                  labelText: AppLocalizations.of(
                                    context,
                                  ).useSelectedPhoto,
                                  onTap: () async {
                                    final selectedFile =
                                        selectedFiles.files.first;
                                    Navigator.pop(
                                      context,
                                      selectedFile.uploadedFileID!,
                                    );
                                  },
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: 8),
                          ButtonWidget(
                            buttonType: ButtonType.secondary,
                            buttonAction: ButtonAction.cancel,
                            labelText: collection.hasCover
                                ? AppLocalizations.of(context).resetToDefault
                                : AppLocalizations.of(context).cancel,
                            icon: collection.hasCover
                                ? Icons.restore_outlined
                                : null,
                            onTap: () async {
                              if (collection.hasCover) {
                                Navigator.pop(context, 0);
                              } else {
                                Navigator.of(context).pop();
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
