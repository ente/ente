import 'dart:io';

import 'package:ente_components/ente_components.dart';
import 'package:ente_events/event_bus.dart';
import "package:ente_strings/ente_strings.dart";
import 'package:ente_ui/components/progress_dialog.dart';
import 'package:ente_ui/pages/base_home_page.dart';
import 'package:ente_ui/utils/dialog_util.dart';
import "package:ente_utils/email_util.dart";
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:locker/core/errors.dart';
import 'package:locker/events/user_details_refresh_event.dart';
import 'package:locker/services/collections/collections_service.dart';
import 'package:locker/services/collections/models/collection.dart';
import 'package:locker/services/files/sync/metadata_updater_service.dart';
import 'package:locker/services/files/upload/file_upload_service.dart';
import 'package:locker/ui/pages/file_upload_screen.dart';
import "package:locker/utils/bottom_sheet_illustration.dart";
import "package:locker/utils/error_sheet.dart";
import 'package:logging/logging.dart';

abstract class UploaderPage extends BaseHomePage {
  const UploaderPage({super.key});
}

enum _UploadFilesOutcome { cancelled, succeeded, failed }

abstract class UploaderPageState<T extends UploaderPage> extends State<T> {
  final _logger = Logger('UploaderPage');

  Collection? get selectedCollection => null;

  void onFileUploadComplete();

  Future<bool> addFile() async {
    final FilePickerResult? result = await FilePicker.pickFiles(
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
        final outcome = await _uploadFiles(selectedFiles);
        return outcome != _UploadFilesOutcome.cancelled;
      }
    }

    return false;
  }

  Future<bool> uploadFiles(List<File> files) async =>
      await _uploadFiles(files) == _UploadFilesOutcome.succeeded;

  Future<_UploadFilesOutcome> _uploadFiles(List<File> files) async {
    var outcome = _UploadFilesOutcome.cancelled;
    var hasUploadError = false;
    var completedPrimaryUploads = 0;
    var didShowDialog = false;
    final l10n = context.strings;
    ProgressDialog? progressDialog;

    try {
      final futures = <Future<void>>[];

      final regularCollections = await CollectionService.instance
          .getCollectionsForUI();

      if (!mounted) {
        return _UploadFilesOutcome.cancelled;
      }

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

      final isUncategorizedUpload =
          uploadResult != null && uploadResult.selectedCollections.isEmpty;
      final isRegularUpload =
          uploadResult != null && uploadResult.selectedCollections.isNotEmpty;

      if (isUncategorizedUpload || isRegularUpload) {
        outcome = _UploadFilesOutcome.failed;
        if (isUncategorizedUpload) {
          final uncategorizedCollection = await CollectionService.instance
              .getOrCreateUncategorizedCollection();
          uploadResult.selectedCollections.add(uncategorizedCollection);
        }

        if (mounted) {
          final dialog = createProgressDialog(
            context,
            l10n.uploadedFilesProgress(completed: 0, total: files.length),
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
                completedPrimaryUploads++;
                completedUploads++;
                if (didShowDialog &&
                    mounted &&
                    !hasUploadError &&
                    progressDialog?.isShowing() == true) {
                  try {
                    progressDialog?.update(
                      message: l10n.uploadedFilesProgress(
                        completed: completedUploads,
                        total: files.length,
                      ),
                    );
                  } catch (e, s) {
                    _logger.warning('Failed to update upload progress', e, s);
                  }
                }

                final postUploadFutures = <Future<dynamic>>[];
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
        if (!hasUploadError) {
          outcome = _UploadFilesOutcome.succeeded;
        }
      }
    } catch (e, s) {
      final didUploadAllFiles =
          files.isNotEmpty && completedPrimaryUploads == files.length;
      outcome = didUploadAllFiles
          ? _UploadFilesOutcome.succeeded
          : _UploadFilesOutcome.failed;
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

    return outcome;
  }

  Future<void> _showUploadFailureError(Object error) async {
    if (error is NoActiveSubscriptionError) {
      await _showUploadErrorSheet(
        context.strings.uploadSubscriptionExpiredErrorTitle,
        context.strings.uploadSubscriptionExpiredErrorBody,
      );
      return;
    }
    if (error is StorageLimitExceededError) {
      await _showUploadErrorSheet(
        context.strings.uploadStorageLimitErrorTitle,
        context.strings.uploadStorageLimitErrorBody,
      );
      return;
    }
    if (error is FileLimitReachedError) {
      await _showUploadErrorSheet(
        context.strings.uploadFileCountLimitErrorTitle,
        context.strings.uploadFileCountLimitErrorBody,
      );
      return;
    }
    if (error is FileTooLargeForPlanError) {
      await _showUploadErrorSheet(
        context.strings.uploadFileTooLargeErrorTitle,
        context.strings.uploadFileTooLargeErrorBody,
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
            label: context.strings.contactSupport,
            onTap: () async {
              await sendEmail(context, to: "support@ente.com", body: message);
            },
          ),
        ],
      ),
    );
  }
}
