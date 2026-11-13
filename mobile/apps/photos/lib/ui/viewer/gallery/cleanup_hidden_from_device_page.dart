import "package:ente_components/ente_components.dart";
import "package:ente_strings/ente_strings.dart";
import "package:flutter/material.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/events/files_updated_event.dart";
import "package:photos/events/local_photos_updated_event.dart";
import "package:photos/models/file_load_result.dart";
import "package:photos/models/gallery_type.dart";
import "package:photos/models/selected_files.dart";
import "package:photos/services/collections_service.dart";
import "package:photos/services/hidden_service.dart";
import "package:photos/ui/components/action_sheet_widget.dart";
import "package:photos/ui/components/buttons/button_widget.dart";
import "package:photos/ui/components/models/button_type.dart";
import "package:photos/ui/viewer/actions/file_selection_overlay_bar.dart";
import "package:photos/ui/viewer/gallery/empty_state.dart";
import "package:photos/ui/viewer/gallery/gallery.dart";
import "package:photos/ui/viewer/gallery/gallery_app_bar_widget.dart";
import "package:photos/ui/viewer/gallery/state/gallery_boundaries_provider.dart";
import "package:photos/ui/viewer/gallery/state/gallery_files_inherited_widget.dart";
import "package:photos/ui/viewer/gallery/state/selection_state.dart";
import "package:photos/utils/delete_file_util.dart";
import "package:photos/utils/dialog_util.dart";

class CleanupHiddenFromDevicePage extends StatefulWidget {
  final VoidCallback? onCleanupComplete;

  const CleanupHiddenFromDevicePage({this.onCleanupComplete, super.key});

  @override
  State<CleanupHiddenFromDevicePage> createState() =>
      _CleanupHiddenFromDevicePageState();
}

class _CleanupHiddenFromDevicePageState
    extends State<CleanupHiddenFromDevicePage> {
  final _selectedFiles = SelectedFiles();

  @override
  Widget build(BuildContext context) {
    final appBar = GalleryAppBarWidget.sliverConfig(
      GalleryType.cleanupHiddenFromDevice,
      context.strings.deleteOnDeviceFiles,
      _selectedFiles,
    );

    final gallery = Gallery(
      appBar: appBar,
      asyncLoader: (creationStartTime, creationEndTime, {limit, asc}) async {
        final files = await CollectionsService.instance
            .getHiddenFilesOnDevice();
        return FileLoadResult(files, false);
      },
      reloadEvent: Bus.instance.on<LocalPhotosUpdatedEvent>(),
      removalEventTypes: const {EventType.deletedFromDevice},
      tagPrefix: "cleanup_hidden_from_device",
      selectedFiles: _selectedFiles,
      enableFileGrouping: false,
      emptyState: EmptyState(text: context.strings.noHiddenFilesOnDevice),
    );

    return GalleryBoundariesProvider(
      child: GalleryFilesState(
        child: Scaffold(
          body: SelectionState(
            selectedFiles: _selectedFiles,
            child: Stack(
              alignment: Alignment.bottomCenter,
              children: [
                gallery,
                FileSelectionOverlayBar(
                  GalleryType.cleanupHiddenFromDevice,
                  _selectedFiles,
                ),
              ],
            ),
          ),
          floatingActionButton: ListenableBuilder(
            listenable: _selectedFiles,
            builder: (context, _) {
              if (_selectedFiles.files.isNotEmpty) {
                return const SizedBox.shrink();
              }
              return Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: FABComponent(
                  label: context.strings.deleteAll,
                  variant: FABComponentVariant.destructive,
                  onTap: _deleteAll,
                ),
              );
            },
          ),
          floatingActionButtonLocation:
              FloatingActionButtonLocation.centerFloat,
          floatingActionButtonAnimator:
              FloatingActionButtonAnimator.noAnimation,
        ),
      ),
    );
  }

  Future<void> _deleteAll() async {
    final allFiles = await CollectionsService.instance.getHiddenFilesOnDevice();
    if (allFiles.isEmpty) return;

    if (!mounted) return;
    final l10n = context.strings;
    if (!mounted) return;
    final actionResult = await showActionSheet(
      context: context,
      title: l10n.deleteFromDeviceQuestion,
      buttons: [
        ButtonWidget(
          labelText: l10n.deleteFromDevice,
          buttonType: ButtonType.neutral,
          buttonSize: ButtonSize.large,
          shouldStickToDarkTheme: true,
          buttonAction: ButtonAction.first,
          shouldSurfaceExecutionStates: true,
          isInAlert: true,
          onTap: () async {
            try {
              await deleteFilesOnDeviceOnly(context, allFiles);
            } catch (e) {
              if (context.mounted) {
                if (!mounted) return;
                await showGenericErrorDialog(context: context, error: e);
              }
              rethrow;
            }
          },
        ),
        ButtonWidget(
          labelText: l10n.cancel,
          buttonType: ButtonType.secondary,
          buttonSize: ButtonSize.large,
          shouldStickToDarkTheme: true,
          buttonAction: ButtonAction.cancel,
          isInAlert: true,
        ),
      ],
      body: l10n.theseItemsWillBeDeletedFromYourDevice,
      actionSheetType: ActionSheetType.defaultActionSheet,
    );

    if (actionResult?.action == ButtonAction.first) {
      widget.onCleanupComplete?.call();
      if (context.mounted) {
        if (!mounted) return;
        Navigator.of(context).pop();
      }
    }
  }
}
