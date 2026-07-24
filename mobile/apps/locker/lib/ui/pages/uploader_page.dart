import 'dart:io';

import 'package:ente_components/ente_components.dart';
import 'package:ente_events/event_bus.dart';
import 'package:ente_ui/components/progress_dialog.dart';
import 'package:ente_ui/pages/base_home_page.dart';
import 'package:ente_ui/utils/dialog_util.dart';
import "package:ente_utils/email_util.dart";
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:locker/core/errors.dart';
import 'package:locker/events/user_details_refresh_event.dart';
import "package:locker/l10n/l10n.dart";
import 'package:locker/services/collections/collections_service.dart';
import 'package:locker/services/collections/models/collection.dart';
import 'package:locker/services/files/sync/metadata_updater_service.dart';
import 'package:locker/services/files/upload/file_upload_service.dart';
import 'package:locker/ui/pages/file_upload_screen.dart';
import "package:locker/utils/bottom_sheet_illustration.dart";
import "package:locker/utils/error_sheet.dart";
import 'package:logging/logging.dart';

/// Abstract base class that provides file upload functionality.
/// Contains common file picking and uploading logic that can be reused
/// across different pages like HomePage and CollectionPage.
abstract class UploaderPage extends BaseHomePage {
  const UploaderPage({super.key});
}

abstract class UploaderPageState<T extends UploaderPage> extends State<T> {
  final _logger = Logger('UploaderPage');

  /// Returns the collection that should be pre-selected in the upload dialog.
  /// Return null to default to uncategorized collection.
  Collection? get selectedCollection => null;

  /// Called after a successful file upload to refresh the UI
  void onFileUploadComplete();

  /// Opens a file picker dialog and uploads the selected file
  Future<bool> addFile() async {
    final FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      allowMultiple: true,
    );

    if (!mounted) {
      return false;
    }

    if (result != null && result.files.isNotEmpty) {
      final selectedFiles = result.files
          .where((file) => file.path != null)
          .map((file) => File(file.path!))
          .toList();

      if (selectedFiles.isNotEmpty) {
        return await uploadFiles(selectedFiles);
      }
    }

    return false;
  }

  Future<bool> uploadFiles(List<File> files) async {
    var didUpload = false;
    var hasUploadError = false;
    var didShowDialog = false;
    final l10n = context.l10n;
    ProgressDialog? progressDialog;

    try {
      final futures = <Future<void>>[];

      final regularCollections = await CollectionService.instance
          .getCollectionsForUI();

      if (!mounted) {
        return false;
      }

      // Navigate to upload screen to get collection selection
      final uploadResult = await Navigator.of(context)
          .push<FileUploadScreenResult>(
            MaterialPageRoute(
              builder: (context) => FileUploadScreen(
                files: files,
                collections: regularCollections,
                selectedCollection: selectedCollection,
              ),
            ),
          );

      // Handle both regular collections and uncategorized (empty set)
      final isUncategorizedUpload =
          uploadResult != null && uploadResult.selectedCollections.isEmpty;
      final isRegularUpload =
          uploadResult != null && uploadResult.selectedCollections.isNotEmpty;

      if (isUncategorizedUpload || isRegularUpload) {
        didUpload = true;
        if (isUncategorizedUpload) {
          // Get the uncategorized collection for upload
          final uncategorizedCollection = await CollectionService.instance
              .getOrCreateUncategorizedCollection();
          uploadResult.selectedCollections.add(uncategorizedCollection);
        }

        if (mounted) {
          final dialog = createProgressDialog(
            context,
            l10n.uploadedFilesProgress(0, files.length),
          );
          progressDialog = dialog;
          didShowDialog = await dialog.show();
        }

        int completedUploads = 0;
        for (final file in files) {
          final fileUploadFuture = FileUploader.instance.upload(
            file,
            uploadResult.selectedCollections.first,
          );
          futures.add(
            fileUploadFuture.then<void>(
              (enteFile) async {
                completedUploads++;
                if (didShowDialog &&
                    mounted &&
                    !hasUploadError &&
                    progressDialog?.isShowing() == true) {
                  try {
                    progressDialog?.update(
                      message: l10n.uploadedFilesProgress(
                        completedUploads,
                        files.length,
                      ),
                    );
                  } catch (e, s) {
                    _logger.warning('Failed to update upload progress', e, s);
                  }
                }

                final postUploadFutures = <Future<dynamic>>[];
                // Add to additional collections if multiple were selected
                for (
                  int cIndex = 1;
                  cIndex < uploadResult.selectedCollections.length;
                  cIndex++
                ) {
                  // Don't trigger a sync for each additional collection – do one
                  // sync at the end after all files are processed.
                  postUploadFutures.add(
                    CollectionService.instance.addToCollection(
                      uploadResult.selectedCollections[cIndex],
                      enteFile,
                      runSync: false,
                    ),
                  );
                }

                if (uploadResult.note.isNotEmpty) {
                  postUploadFutures.add(
                    MetadataUpdaterService.instance.editFileCaption(
                      enteFile,
                      uploadResult.note,
                    ),
                  );
                }

                await Future.wait(postUploadFutures);
              },
              onError: (Object e, StackTrace s) async {
                completedUploads++;
                _logger.severe('File upload failed', e, s);
                if (hasUploadError) {
                  return;
                }
                hasUploadError = true;
                if (didShowDialog && progressDialog?.isShowing() == true) {
                  await progressDialog?.hide();
                  didShowDialog = false;
                }
                if (mounted) {
                  await _showUploadFailureError(e);
                }
              },
            ),
          );
        }

        if (futures.isNotEmpty) {
          await Future.wait(futures);

          if (mounted) {
            onFileUploadComplete();
          }
          Bus.instance.fire(UserDetailsRefreshEvent());

          await CollectionService.instance.sync().catchError((e) {
            _logger.warning('Background sync failed after upload', e);
          });
        }
      }
    } catch (e, s) {
      _logger.severe('Failed to complete file upload', e, s);
      if (didShowDialog && progressDialog?.isShowing() == true) {
        await progressDialog?.hide();
        didShowDialog = false;
      }
      if (mounted) {
        await _showUploadFailureError(e);
      }
    } finally {
      if (didShowDialog && progressDialog?.isShowing() == true) {
        await progressDialog?.hide();
        didShowDialog = false;
      }
    }

    return didUpload;
  }

  Future<void> _showUploadFailureError(Object error) async {
    if (error is NoActiveSubscriptionError) {
      await _showUploadErrorSheet(
        context.l10n.uploadSubscriptionExpiredErrorTitle,
        context.l10n.uploadSubscriptionExpiredErrorBody,
      );
      return;
    }
    if (error is StorageLimitExceededError) {
      await _showUploadErrorSheet(
        context.l10n.uploadStorageLimitErrorTitle,
        context.l10n.uploadStorageLimitErrorBody,
      );
      return;
    }
    if (error is FileLimitReachedError) {
      await _showUploadErrorSheet(
        context.l10n.uploadFileCountLimitErrorTitle,
        context.l10n.uploadFileCountLimitErrorBody,
      );
      return;
    }
    if (error is FileTooLargeForPlanError) {
      await _showUploadErrorSheet(
        context.l10n.uploadFileTooLargeErrorTitle,
        context.l10n.uploadFileTooLargeErrorBody,
      );
      return;
    }
    await showLockerErrorSheet(context, error);
  }

  Future<void> _showUploadErrorSheet(String title, String message) async {
    await showBottomSheetComponent(
      context: context,
      isDismissible: true,
      enableDrag: true,
      builder: (_) => BottomSheetComponent(
        title: title,
        message: message,
        illustration: LockerBottomSheetIllustration.warningGrey,
        actions: [
          ButtonComponent(
            label: context.l10n.contactSupport,
            onTap: () async {
              await sendEmail(context, to: "support@ente.com", body: message);
            },
          ),
        ],
      ),
    );
  }
}
