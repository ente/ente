import 'dart:io';

import 'package:backup_exclusion/backup_exclusion.dart';
import 'package:ente_auth/l10n/l10n.dart';
import 'package:ente_auth/models/code.dart';
import 'package:ente_auth/ui/settings/data/import/google_auth_qr_parser.dart';
import 'package:ente_auth/utils/dialog_util.dart';
import 'package:ente_qr/ente_qr.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

const _pickedImagesDirectoryName = 'picked_images';

class GalleryImportResult {
  final Code? code;
  final GoogleAuthMigration? googleAuthMigration;

  const GalleryImportResult.code(Code this.code) : googleAuthMigration = null;

  const GalleryImportResult.googleAuthMigration(
    GoogleAuthMigration this.googleAuthMigration,
  ) : code = null;

  List<Code>? get googleAuthCodes => googleAuthMigration?.codes;
}

Future<Directory> _getPickedImagesDirectory({
  Future<Directory> Function()? documentsDirectoryProvider,
}) async {
  final documentsDirectory =
      await (documentsDirectoryProvider ?? getApplicationDocumentsDirectory)();
  return Directory(p.join(documentsDirectory.path, _pickedImagesDirectoryName));
}

class _PickedImageCleanup {
  const _PickedImageCleanup(this.file, {required this.excludeParentFromBackup});

  final File file;
  final bool excludeParentFromBackup;
}

Future<_PickedImageCleanup?> _getPickedImageCleanup(
  String imagePath, {
  bool includeTemporaryDirectory = false,
  Future<Directory> Function()? documentsDirectoryProvider,
  Future<Directory> Function()? temporaryDirectoryProvider,
  Directory? systemTemporaryDirectory,
}) async {
  if (!Platform.isIOS) {
    return null;
  }

  final pickedImagesDirectory = await _getPickedImagesDirectory(
    documentsDirectoryProvider: documentsDirectoryProvider,
  );
  if (p.isWithin(
    p.normalize(pickedImagesDirectory.path),
    p.normalize(imagePath),
  )) {
    return _PickedImageCleanup(File(imagePath), excludeParentFromBackup: true);
  }

  if (!includeTemporaryDirectory) return null;
  final temporaryDirectories = <Directory>[
    await (temporaryDirectoryProvider ?? getTemporaryDirectory)(),
    systemTemporaryDirectory ?? Directory.systemTemp,
  ];
  for (final temporaryDirectory in temporaryDirectories) {
    if (p.isWithin(
      p.normalize(temporaryDirectory.path),
      p.normalize(imagePath),
    )) {
      return _PickedImageCleanup(
        File(imagePath),
        excludeParentFromBackup: false,
      );
    }
  }
  return null;
}

Future<void> _clearPickedImagesDirectoryContents(
  Directory pickedImagesDirectory, {
  Logger? logger,
}) async {
  try {
    await for (final entity in pickedImagesDirectory.list()) {
      await entity.delete(recursive: true);
    }
  } catch (e, stackTrace) {
    logger?.warning(
      'Failed to clear stale picked_images contents',
      e,
      stackTrace,
    );
  }
}

Future<void> _cleanupPickedGalleryImageIfNeeded(
  File imageFile, {
  Logger? logger,
}) async {
  if (!await imageFile.exists()) {
    return;
  }

  try {
    await imageFile.delete();
  } catch (e, stackTrace) {
    logger?.warning('Failed to delete picked gallery image', e, stackTrace);
  }
}

Future<void> cleanupPickedImagesOnStartup({Logger? logger}) async {
  if (!Platform.isIOS) {
    return;
  }

  final pickedImagesDirectory = await _getPickedImagesDirectory();
  if (!await pickedImagesDirectory.exists()) {
    return;
  }

  await excludeFromBackup(pickedImagesDirectory.path);
  await _clearPickedImagesDirectoryContents(
    pickedImagesDirectory,
    logger: logger,
  );
}

GalleryImportResult parseQrImportPayload(String qrCodeData) {
  if (isGoogleAuthExportQr(qrCodeData)) {
    final migration = parseGoogleAuthMigration(qrCodeData);
    if (migration.codes.isEmpty) {
      throw const FormatException('No Google Authenticator codes found');
    }
    return GalleryImportResult.googleAuthMigration(migration);
  }
  return GalleryImportResult.code(Code.fromOTPAuthUrl(qrCodeData));
}

/// Prompts the user to pick an image and tries to extract auth codes from it.
/// Returns the parsed QR import result when successful, otherwise null.
Future<GalleryImportResult?> pickCodeFromImage(
  BuildContext context, {
  Logger? logger,
  bool pickFromFiles = false,
}) async {
  final l10n = context.l10n;

  try {
    if (!context.mounted) return null;
    final FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: pickFromFiles ? FileType.custom : FileType.image,
      allowedExtensions: pickFromFiles
          ? const ['png', 'jpg', 'jpeg', 'webp', 'heic']
          : null,
    );

    if (result == null || result.files.single.path == null) {
      return null;
    }

    final String imagePath = result.files.single.path!;
    final pickedImageCleanup = await _getPickedImageCleanup(
      imagePath,
      includeTemporaryDirectory: pickFromFiles,
    );
    if (pickedImageCleanup?.excludeParentFromBackup ?? false) {
      await excludeFromBackup(pickedImageCleanup!.file.parent.path);
    }

    try {
      final qrResult = await EnteQr().scanQrFromImage(
        imagePath,
        tryOriginalResolution: true,
      );

      if (qrResult.success && qrResult.content != null) {
        try {
          return parseQrImportPayload(qrResult.content!);
        } catch (e, stackTrace) {
          logger?.severe('Error adding code from QR scan', e, stackTrace);
          if (!context.mounted) return null;
          await showErrorDialog(
            context,
            l10n.errorInvalidQRCode,
            l10n.errorInvalidQRCodeBody,
            showContactSupport: false,
          );
          return null;
        }
      } else {
        logger?.warning('QR scan failed: ${qrResult.error}');
        if (!context.mounted) return null;
        await showErrorDialog(
          context,
          l10n.errorNoQRCode,
          qrResult.error ?? l10n.errorNoQRCode,
          showContactSupport: false,
        );
        return null;
      }
    } catch (e, stackTrace) {
      logger?.severe('Failed to import from gallery', e, stackTrace);
      if (!context.mounted) return null;
      await showErrorDialog(
        context,
        l10n.errorGenericTitle,
        l10n.errorGenericBody,
      );
      return null;
    } finally {
      if (pickedImageCleanup != null) {
        await _cleanupPickedGalleryImageIfNeeded(
          pickedImageCleanup.file,
          logger: logger,
        );
      }
    }
  } catch (e, stackTrace) {
    logger?.severe('Failed to import from gallery', e, stackTrace);
    if (!context.mounted) return null;
    await showErrorDialog(
      context,
      l10n.errorGenericTitle,
      l10n.errorGenericBody,
    );
    return null;
  }
}
