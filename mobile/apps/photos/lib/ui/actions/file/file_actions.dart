import "dart:async";
import "dart:io";

import "package:ente_components/ente_components.dart";
import "package:flutter/material.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/events/details_sheet_event.dart";
import "package:photos/generated/l10n.dart";
import "package:photos/models/file/extensions/file_props.dart";
import 'package:photos/models/file/file.dart';
import 'package:photos/module/metadata/panorama.dart';
import "package:photos/service_locator.dart";
import "package:photos/services/media_store_service.dart";
import "package:photos/theme/ente_theme.dart";
import "package:photos/ui/notification/toast.dart";
import 'package:photos/ui/viewer/file/file_details_widget.dart';
import "package:photos/utils/delete_file_util.dart";

Future<void> showSingleFileDeleteSheet(
  BuildContext context,
  EnteFile file, {
  Function(EnteFile)? onFileRemoved,
  bool isLocalOnlyContext = false,
}) async {
  final l10n = AppLocalizations.of(context);
  final bool isLocal = file.localID != null;
  final bool isRemote = file.uploadedFileID != null;
  if (isLocalGalleryMode) {
    if (!isLocal) {
      showShortToast(context, l10n.noDeviceThatCanBeDeleted);
      return;
    }
    if (Platform.isAndroid && await MediaStoreService.canManageMedia()) {
      if (!context.mounted) return;
      await showBottomSheetComponent<bool>(
        context: context,
        useRootNavigator: Platform.isIOS,
        builder: (_) => DeleteConfirmationSheet(
          count: 1,
          isLocal: isLocal,
          isRemote: false,
          onDeleteFromLocal: () async {
            final deletedFiles = await deleteFilesOnDeviceOnly(context, [file]);
            if (deletedFiles.isNotEmpty &&
                ((isLocal && !isRemote) || isLocalOnlyContext)) {
              onFileRemoved?.call(file);
            }
          },
          onDeleteFromRemote: () async {
            throw AssertionError("delete from remote in local gallery mode");
          },
          onDeleteFromBoth: () async {
            throw AssertionError("delete from both in local gallery mode");
          },
        ),
      );
    } else {
      if (!context.mounted) return;
      final deletedFiles = await deleteFilesOnDeviceOnly(context, [file]);
      if (deletedFiles.isNotEmpty &&
          ((isLocal && !isRemote) || isLocalOnlyContext)) {
        onFileRemoved?.call(file);
      }
    }
    return;
  }
  if (!isLocal && !isRemote) {
    throw AssertionError("Unexpected state");
  }
  final didDelete = await showBottomSheetComponent<bool>(
    context: context,
    useRootNavigator: Platform.isIOS,
    builder: (_) => DeleteConfirmationSheet(
      isLocal: isLocal,
      isRemote: isRemote,
      count: 1,
      onDeleteFromLocal: () async {
        final deletedFiles = await deleteFilesOnDeviceOnly(context, [file]);
        if (deletedFiles.isNotEmpty &&
            ((isLocal && !isRemote) || isLocalOnlyContext)) {
          onFileRemoved?.call(file);
        }
      },
      onDeleteFromRemote: () async {
        await deleteFilesFromRemoteOnly(context, [file]);
        if (!context.mounted) return;
        showShortToast(context, l10n.movedToTrash);
        if (((isRemote && !isLocal) || !isLocalOnlyContext)) {
          onFileRemoved?.call(file);
        }
      },
      onDeleteFromBoth: () async {
        await deleteFilesFromEverywhere(context, [file]);
        onFileRemoved?.call(file);
      },
    ),
  );
  if (didDelete == true && isLocal) {
    if (!context.mounted) return;
    await showMediaManagementHintSheet(context);
  }
}

Future<void> showDetailsSheet(BuildContext context, EnteFile file) async {
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
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _DraggableDetailsSheet(file: file),
  );
  Bus.instance.fire(
    DetailsSheetEvent(
      localID: file.localID,
      uploadedFileID: file.uploadedFileID,
      opened: false,
    ),
  );
}

class _DraggableDetailsSheet extends StatefulWidget {
  final EnteFile file;
  const _DraggableDetailsSheet({required this.file});

  @override
  State<_DraggableDetailsSheet> createState() => _DraggableDetailsSheetState();
}

class _DraggableDetailsSheetState extends State<_DraggableDetailsSheet> {
  final _sheetController = DraggableScrollableController();
  bool _isExpanded = false;

  @override
  void initState() {
    super.initState();
    _sheetController.addListener(_onSheetSizeChanged);
  }

  @override
  void dispose() {
    _sheetController.removeListener(_onSheetSizeChanged);
    _sheetController.dispose();
    super.dispose();
  }

  void _onSheetSizeChanged() {
    final isNowExpanded = _sheetController.size >= 0.75;
    if (isNowExpanded != _isExpanded) {
      setState(() {
        _isExpanded = isNowExpanded;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isKeyboardOpen = MediaQuery.of(context).viewInsets.bottom > 60;
    final disableSnap = isKeyboardOpen || _isExpanded;
    return DraggableScrollableSheet(
      controller: _sheetController,
      initialChildSize: disableSnap ? 0.95 : 0.75,
      minChildSize: disableSnap ? 0.75 : 0.5,
      maxChildSize: 0.95,
      snap: !disableSnap,
      snapSizes: disableSnap ? null : const [0.75],
      expand: false,
      builder: (context, scrollController) => Container(
        decoration: BoxDecoration(
          color: getEnteColorScheme(context).backgroundElevated,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
        ),
        child: FileDetailsWidget(
          widget.file,
          scrollController: scrollController,
        ),
      ),
    );
  }
}
