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
  await showBottomSheetComponent(
    context: context,
    builder: (_) => FileDetailsWidget(file),
  );
  Bus.instance.fire(
    DetailsSheetEvent(
      localID: file.localID,
      uploadedFileID: file.uploadedFileID,
      opened: false,
    ),
  );
}
