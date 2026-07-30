import "dart:io";
import "dart:typed_data";

import "package:ente_components/ente_components.dart";
import "package:ente_ui/utils/dialog_util.dart";
import "package:ente_ui/utils/toast_util.dart";
import "package:ente_utils/email_util.dart";
import "package:file_saver/file_saver.dart";
import "package:flutter/material.dart";
import "package:locker/l10n/l10n.dart";
import "package:locker/models/info/info_item.dart";
import "package:locker/services/collections/collections_service.dart";
import "package:locker/services/files/download/file_downloader.dart"
    as file_downloader;
import "package:locker/services/files/offline/offline_file_storage.dart";
import "package:locker/services/files/sync/models/file.dart";
import "package:locker/services/info_file_service.dart";
import "package:locker/ui/pages/account_credentials_page.dart";
import "package:locker/ui/pages/base_info_page.dart";
import "package:locker/ui/pages/emergency_contact_page.dart";
import "package:locker/ui/pages/personal_note_page.dart";
import "package:locker/ui/pages/physical_records_page.dart";
import "package:locker/utils/bottom_sheet_illustration.dart";
import "package:locker/utils/error_sheet.dart";
import "package:logging/logging.dart";
import "package:open_file/open_file.dart";
import "package:path/path.dart" as p;

class FileUtil {
  static final Logger _logger = Logger("FileUtil");

  static Future<void> openFile(BuildContext context, EnteFile file) async {
    final l10n = context.l10n;

    Future<void> showOpenFileError({
      required String error,
      ResultType? resultType,
    }) async {
      if (!context.mounted) {
        return;
      }
      await _showOpenFileError(
        context,
        error: error,
        resultType: resultType,
        lockerFile: file,
      );
    }

    if (InfoFileService.instance.isInfoFile(file)) {
      return _openInfoFile(context, file);
    }

    if (file.uploadedFileID == null) {
      await showLockerErrorSheet(context, Exception(l10n.errorOpeningFile));
      return;
    }

    final cachedDecryptedFile = File(getCachedDecryptedFilePath(file));
    if (await cachedDecryptedFile.exists()) {
      final cachedSize = await cachedDecryptedFile.length();
      if (cachedSize > 0) {
        await _launchFile(
          cachedDecryptedFile,
          displayName: file.displayName,
          lockerFile: file,
          showError: showOpenFileError,
        );
        return;
      }
      await cachedDecryptedFile.delete();
    }

    final dialog = context.mounted
        ? createProgressDialog(context, l10n.downloading, isDismissible: false)
        : null;

    try {
      await dialog?.show();
      final fileKey = await CollectionService.instance.getFileKey(file);
      void progressCallback(int downloaded, int total) {
        if (!context.mounted) {
          return;
        }
        if (total > 0 && downloaded >= 0) {
          final percentage = ((downloaded / total) * 100).clamp(0, 100).round();
          dialog?.update(message: l10n.downloadingProgress(percentage));
        } else {
          dialog?.update(message: l10n.downloading);
        }
      }

      final decryptedFile = await file_downloader.openFile(
        file,
        fileKey,
        progressCallback: progressCallback,
      );

      await dialog?.hide();

      if (decryptedFile != null) {
        await _launchFile(
          decryptedFile,
          displayName: file.displayName,
          lockerFile: file,
          showError: showOpenFileError,
        );
      } else if (context.mounted) {
        await showBottomSheetComponent(
          context: context,
          builder: (_) => BottomSheetComponent(
            title: l10n.downloadFailed,
            message: l10n.failedToDownloadOrDecrypt,
            illustration: LockerBottomSheetIllustration.warningGrey,
            actions: [
              ButtonComponent(
                label: l10n.contactSupport,
                onTap: () async {
                  await sendLogs(context, "support@ente.com", postShare: () {});
                },
              ),
            ],
          ),
        );
      }
    } catch (e) {
      await dialog?.hide();
      if (context.mounted) {
        await showLockerErrorSheet(context, e);
      }
    }
  }

  static Future<bool> downloadFile(BuildContext context, EnteFile file) {
    return _downloadFiles(context, [file]);
  }

  static Future<bool> downloadFiles(
    BuildContext context,
    List<EnteFile> files,
  ) {
    return _downloadFiles(context, files);
  }

  static Future<bool> _downloadFiles(
    BuildContext context,
    List<EnteFile> files,
  ) async {
    if (files.isEmpty) {
      return false;
    }

    final total = files.length;
    final l10n = context.l10n;
    final dialog = createProgressDialog(
      context,
      "${l10n.downloading} 0/$total",
      isDismissible: false,
    );

    await dialog.show();

    var index = 0;
    final savedNames = <String>[];
    final savedPaths = <String>[];
    var hasShownInfoSkipToast = false;

    try {
      for (final file in files) {
        index += 1;
        if (context.mounted) {
          dialog.update(
            message: '${l10n.downloading} ${file.displayName} ($index/$total)',
          );
        }

        // Skip info items for now; they are meant to be viewed in-app.
        if (InfoFileService.instance.isInfoFile(file)) {
          _logger.fine(
            'Skipping info file download (ID: ${file.uploadedFileID})',
          );
          if (!hasShownInfoSkipToast && context.mounted) {
            hasShownInfoSkipToast = true;
            showToast(
              context,
              'Some items were skipped as they cannot be downloaded yet',
            );
          }
          continue;
        }

        final sanitizedName = _sanitizeFileName(file.displayName);
        final baseName = _baseNameWithoutExtension(sanitizedName);
        final fileExtension = _extensionWithoutDot(file.displayName);

        final String? savedPath = await _saveRegularFile(
          file: file,
          targetFileName: fileExtension.isEmpty
              ? baseName
              : "$baseName.$fileExtension",
          fileExtension: fileExtension,
          onProgress: (percentage) {
            if (context.mounted) {
              dialog.update(
                message:
                    '${l10n.downloadingProgress(percentage)} ($index/$total)',
              );
            }
          },
        );

        savedNames.add(file.displayName);
        if (savedPath != null) {
          savedPaths.add(savedPath);
        }
      }

      if (savedNames.isNotEmpty) {
        final message = savedNames.length == 1
            ? '${savedNames.first} saved'
            : '${savedNames.length} files saved';
        _logger.info('${savedPaths.length} files saved');
        if (context.mounted) {
          showToast(context, message);
        }
      }

      return true;
    } catch (e, s) {
      _logger.severe('Failed to save files', e, s);
      if (context.mounted) {
        if (e is UnsupportedError) {
          showToast(context, 'This file type is not supported for download');
        } else {
          showToast(context, l10n.failedToDownloadOrDecrypt);
        }
      }
      return false;
    } finally {
      try {
        await dialog.hide();
      } catch (e) {
        _logger.warning('Failed to hide progress dialog: $e');
      }
    }
  }

  static Future<String?> _saveRegularFile({
    required EnteFile file,
    required String targetFileName,
    required String fileExtension,
    required ValueChanged<int> onProgress,
  }) async {
    final fileKey = await CollectionService.instance.getFileKey(file);

    final decryptedFile = await file_downloader.openFile(
      file,
      fileKey,
      useTemporaryDecryptedFile: true,
      progressCallback: (downloaded, total) {
        if (total > 0 && downloaded >= 0) {
          final percentage = ((downloaded / total) * 100).clamp(0, 100).round();
          onProgress(percentage);
        }
      },
    );

    if (decryptedFile == null) {
      throw Exception('Failed to download file (ID: ${file.uploadedFileID})');
    }

    try {
      // Use system file picker on both Android and iOS to let user
      // choose where to save the file.
      final fileBytes = await decryptedFile.readAsBytes();
      final baseName = _baseNameWithoutExtension(targetFileName);
      final savedPath = await _saveFile(
        bytes: fileBytes,
        fileName: baseName,
        fileExtension: fileExtension,
      );

      if (savedPath == null) {
        throw Exception('Failed to save file');
      }

      try {
        onProgress(100);
      } catch (e) {
        _logger.fine('Unable to update progress dialog after save: $e');
      }
      return savedPath;
    } finally {
      try {
        await decryptedFile.delete();
      } catch (e) {
        _logger.fine(
          'Unable to delete temporary file ${decryptedFile.path}: $e',
        );
      }
    }
  }

  /// Saves files using the platform's system file picker.
  /// On Android and iOS this shows a system sheet allowing the user
  /// to choose where to save the file.
  static Future<String?> _saveFile({
    required Uint8List bytes,
    required String fileName,
    required String fileExtension,
  }) async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      _logger.warning('File saving only supported on Android and iOS');
      return null;
    }

    try {
      final baseName = _baseNameWithoutExtension(fileName);

      final savedPath = await FileSaver.instance.saveAs(
        name: baseName,
        bytes: bytes,
        fileExtension: fileExtension,
        mimeType: MimeType.other,
      );

      _logger.info('File saved successfully');
      return savedPath;
    } catch (e, s) {
      _logger.severe('Failed to save file', e, s);
      return null;
    }
  }

  static String _sanitizeFileName(String name) {
    final sanitized = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
    return sanitized.isEmpty ? "file" : sanitized;
  }

  static String _baseNameWithoutExtension(String name) {
    final base = p.basenameWithoutExtension(name).trim();
    return base.isEmpty ? "file" : base;
  }

  static String _extensionWithoutDot(String name) {
    final ext = p.extension(name);
    if (ext.isEmpty) {
      return '';
    }
    return ext.replaceAll('.', '').replaceAll(RegExp(r'[\\/:*?"<>|]'), '');
  }

  static Future<void> _openInfoFile(BuildContext context, EnteFile file) async {
    try {
      final infoItem = InfoFileService.instance.extractInfoFromFile(file);
      if (infoItem == null) {
        await showBottomSheetComponent(
          context: context,
          builder: (_) => BottomSheetComponent(
            title: context.l10n.errorOpeningFile,
            message: context.l10n.unableToExtractFileInformation,
            illustration: LockerBottomSheetIllustration.warningGrey,
            actions: [
              ButtonComponent(
                label: context.l10n.contactSupport,
                onTap: () async {
                  await sendLogs(context, "support@ente.com", postShare: () {});
                },
              ),
            ],
          ),
        );
        return;
      }

      Widget page;
      switch (infoItem.type) {
        case InfoType.note:
          page = PersonalNotePage(mode: InfoPageMode.view, existingFile: file);
          break;
        case InfoType.accountCredential:
          page = AccountCredentialsPage(
            mode: InfoPageMode.view,
            existingFile: file,
          );
          break;
        case InfoType.physicalRecord:
          page = PhysicalRecordsPage(
            mode: InfoPageMode.view,
            existingFile: file,
          );
          break;
        case InfoType.emergencyContact:
          page = EmergencyContactPage(
            mode: InfoPageMode.view,
            existingFile: file,
          );
          break;
      }

      await Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (context) => page));
    } catch (e) {
      if (context.mounted) {
        await showLockerErrorSheet(context, e);
      }
    }
  }

  static Future<void> _launchFile(
    File file, {
    String? displayName,
    EnteFile? lockerFile,
    required Future<void> Function({
      required String error,
      ResultType? resultType,
    })
    showError,
  }) async {
    File fileToOpen = file;

    try {
      fileToOpen = await _prepareOpenFile(
        file,
        displayName: displayName,
        lockerFile: lockerFile,
      );

      if (!await fileToOpen.exists() || await fileToOpen.length() == 0) {
        throw Exception("File is missing or empty");
      }

      final result = await OpenFile.open(fileToOpen.path);
      if (result.type != ResultType.done) {
        await showError(error: result.message, resultType: result.type);
      }
    } catch (e) {
      await showError(error: e.toString());
    }
  }

  static Future<File> _prepareOpenFile(
    File file, {
    required String? displayName,
    required EnteFile? lockerFile,
  }) async {
    final contentExtension = getPreferredFileExtension(
      lockerFile,
      fallbackPath: file.path,
      fallbackName: displayName,
    );

    final launchName = _openHandoffFileName(
      displayName: displayName,
      lockerFile: lockerFile,
      contentExtension: contentExtension,
    );
    final fileDirectoryName =
        lockerFile?.uploadedFileID?.toString() ??
        file.path.hashCode.toUnsigned(32).toRadixString(16);
    final launchDir = Directory(
      p.join(
        getOpenHandoffDirectoryPath(),
        fileDirectoryName,
        DateTime.now().microsecondsSinceEpoch.toString(),
      ),
    );

    try {
      await launchDir.create(recursive: true);
      final launchPath = p.join(launchDir.path, launchName);
      return await file.copy(launchPath);
    } catch (_) {
      throw Exception("Failed to prepare file for opening");
    }
  }

  @visibleForTesting
  static Future<File> prepareOpenFileForTest(
    File file, {
    required String? displayName,
    required EnteFile? lockerFile,
  }) {
    return _prepareOpenFile(
      file,
      displayName: displayName,
      lockerFile: lockerFile,
    );
  }

  static String _openHandoffFileName({
    required String? displayName,
    required EnteFile? lockerFile,
    required String contentExtension,
  }) {
    final rawName = displayName != null && displayName.trim().isNotEmpty
        ? displayName
        : lockerFile?.uploadedFileID != null
        ? "file-${lockerFile!.uploadedFileID}"
        : "file";
    final sanitizedName = _sanitizeFileName(p.basename(rawName));
    final sanitizedExtension = p.extension(sanitizedName);
    if (contentExtension.isEmpty ||
        sanitizedExtension.toLowerCase() == contentExtension.toLowerCase()) {
      return sanitizedName;
    }
    return "${_baseNameWithoutExtension(sanitizedName)}$contentExtension";
  }

  static Future<void> _showOpenFileError(
    BuildContext context, {
    required String error,
    ResultType? resultType,
    EnteFile? lockerFile,
  }) async {
    await showBottomSheetComponent(
      context: context,
      builder: (_) => BottomSheetComponent(
        title: context.l10n.oops,
        message: _openFileErrorMessage(context, error, resultType: resultType),
        illustration: LockerBottomSheetIllustration.warningGrey,
        actions: [
          ButtonComponent(
            label: context.l10n.download,
            onTap: () async {
              Navigator.of(context).pop();
              await downloadFile(context, lockerFile!);
            },
          ),
        ],
      ),
    );
  }

  static String _openFileErrorMessage(
    BuildContext context,
    String error, {
    ResultType? resultType,
  }) {
    if (resultType == ResultType.noAppToOpen) {
      return context.l10n.noAppToOpenFileDownloadInstead;
    }

    final cleaned = error
        .replaceFirst(RegExp(r"^Exception:\s*"), "")
        .replaceAll("。", ".")
        .trim();
    return context.l10n.couldNotOpenFile(
      cleaned.isEmpty ? context.l10n.noAppToOpenFileDownloadInstead : cleaned,
    );
  }
}
