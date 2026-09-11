import "package:ente_components/ente_components.dart";
import "package:ente_strings/ente_strings.dart";
import "package:flutter/material.dart";
import "package:hugeicons/hugeicons.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/events/people_changed_event.dart";
import "package:photos/models/file_load_result.dart";
import "package:photos/models/ml/face/person.dart";
import "package:photos/models/selected_files.dart";
import "package:photos/services/machine_learning/face_ml/person/person_service.dart";
import "package:photos/services/search_service.dart";
import "package:photos/ui/notification/toast.dart";
import "package:photos/ui/viewer/gallery/gallery.dart";
import "package:photos/ui/viewer/gallery/state/gallery_files_inherited_widget.dart";

Future<dynamic> showPersonAvatarPhotoSheet(
  BuildContext context,
  PersonEntity person,
) async {
  return await showBottomSheetComponent(
    context: context,
    builder: (_) => PickPersonCoverPhotoWidget(person),
    enableDrag: true,
  );
}

class PickPersonCoverPhotoWidget extends StatefulWidget {
  final PersonEntity personEntity;

  const PickPersonCoverPhotoWidget(this.personEntity, {super.key});

  @override
  State<PickPersonCoverPhotoWidget> createState() =>
      _PickPersonCoverPhotoWidgetState();
}

class _PickPersonCoverPhotoWidgetState
    extends State<PickPersonCoverPhotoWidget> {
  late final SelectedFiles _selectedFiles;

  @override
  void initState() {
    super.initState();
    _selectedFiles = SelectedFiles()..addListener(_onSelectionChanged);
  }

  @override
  void dispose() {
    _selectedFiles.dispose();
    super.dispose();
  }

  void _onSelectionChanged() => setState(() {});

  Future<FileLoadResult> loadPersonFiles() async {
    final sortedFiles = await SearchService.instance.getFilesForPersonID(
      widget.personEntity.remoteID,
      includeManualAssigned: false,
      sortOnTime: true,
    );
    return FileLoadResult(sortedFiles, false);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.strings;
    final hasSelection = _selectedFiles.files.isNotEmpty;

    return SizedBox(
      height: MediaQuery.sizeOf(context).height,
      child: BottomSheetComponent(
        header: const _PickPersonCoverPhotoHeader(),
        showCloseButton: false,
        padding: const EdgeInsets.symmetric(vertical: Spacing.xl),
        content: Expanded(
          child: GalleryFilesState(
            child: Gallery(
              asyncLoader:
                  (creationStartTime, creationEndTime, {limit, asc}) async {
                    final FileLoadResult result = await loadPersonFiles();
                    return result;
                  },
              tagPrefix: "pick_center_point_gallery",
              selectedFiles: _selectedFiles,
              limitSelectionToOne: true,
              showSelectAll: false,
              disablePinnedGroupHeader: true,
              disableVerticalPaddingForScrollbar: true,
            ),
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Spacing.xl),
            child: ButtonComponent(
              isDisabled: !hasSelection,
              label: l10n.useSelectedPhoto,
              density: ButtonComponentDensity.compact,
              shouldShowSuccessState: false,
              onTap: hasSelection
                  ? () async {
                      final selectedFile = _selectedFiles.files.first;
                      final result = await PersonService.instance.updateAvatar(
                        widget.personEntity,
                        selectedFile,
                      );
                      Bus.instance.fire(
                        PeopleChangedEvent(
                          type: PeopleEventType.saveOrEditPerson,
                          person: result.person,
                        ),
                      );
                      if (!context.mounted) return;
                      if (result.contactPictureUpdateFailed) {
                        showShortToast(
                          context,
                          "Failed to update contact picture",
                        );
                      }
                      Navigator.pop(context, result.person);
                    }
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _PickPersonCoverPhotoHeader extends StatelessWidget {
  const _PickPersonCoverPhotoHeader();

  @override
  Widget build(BuildContext context) {
    final l10n = context.strings;
    final colors = context.componentColors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Spacing.xl),
      child: SizedBox(
        height: 38,
        child: Row(
          children: [
            Expanded(
              child: Text(
                l10n.selectCoverPhoto,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyles.h1Bold.copyWith(color: colors.textBase),
              ),
            ),
            const SizedBox(width: Spacing.md),
            IconButtonComponent(
              tooltip: l10n.close,
              variant: IconButtonComponentVariant.circular,
              shouldSurfaceExecutionStates: false,
              icon: const HugeIcon(
                icon: HugeIcons.strokeRoundedCancel01,
                size: IconSizes.small,
              ),
              onTap: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );
  }
}
