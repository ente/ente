import 'package:locker/models/file_type.dart';
import 'package:locker/models/info/info_item.dart';
import 'package:locker/services/collections/models/collection.dart';
import 'package:locker/services/files/sync/metadata_updater_service.dart';
import 'package:locker/services/files/sync/models/file.dart';
import 'package:locker/services/files/sync/models/file_magic.dart';
import 'package:locker/services/files/upload/file_upload_service.dart';
import 'package:logging/logging.dart';

class InfoFileService {
  static final InfoFileService instance = InfoFileService._privateConstructor();
  InfoFileService._privateConstructor();

  final _logger = Logger('InfoFileService');

  Future<EnteFile> createAndUploadInfoFile({
    required InfoItem infoItem,
    required Collection collection,
  }) async {
    try {
      final enteFile = EnteFile();
      enteFile.fileType = FileType.info;
      enteFile.collectionID = collection.id;

      enteFile.title = getInfoFileTitle(infoItem);

      final now = DateTime.now().millisecondsSinceEpoch;
      enteFile.creationTime = now;
      enteFile.modificationTime = now;

      final pubMagicMetadata = PubMagicMetadata(
        info: {'type': infoItem.type.name, 'data': infoItem.data.toJson()},
        noThumb: true,
      );
      enteFile.pubMagicMetadata = pubMagicMetadata;

      final uploadedFile = await _uploadInfoFile(enteFile, collection);

      _logger.info(
        'Successfully uploaded info file (ID: ${uploadedFile.uploadedFileID})',
      );
      return uploadedFile;
    } catch (e, s) {
      _logger.severe('Failed to create and upload info file', e, s);
      rethrow;
    }
  }

  Future<bool> updateInfoFile({
    required EnteFile existingFile,
    required InfoItem updatedInfoItem,
  }) async {
    try {
      final infoData = {
        'type': updatedInfoItem.type.name,
        'data': updatedInfoItem.data.toJson(),
      };

      final Map<String, dynamic> metadataUpdates = {infoKey: infoData};

      // Use displayName (which considers editedName) instead of title (original name)
      final updatedTitle = getInfoFileTitle(updatedInfoItem);
      if (existingFile.displayName != updatedTitle) {
        metadataUpdates[editNameKey] = updatedTitle;
        metadataUpdates[editTimeKey] = DateTime.now().millisecondsSinceEpoch;
      }

      final success = await MetadataUpdaterService.instance.updateFileMetadata(
        existingFile,
        metadataUpdates,
      );

      if (success) {
        _logger.info(
          'Successfully updated info file (ID: ${existingFile.uploadedFileID})',
        );
        return true;
      } else {
        throw Exception('Failed to update file metadata on server');
      }
    } catch (e, s) {
      _logger.severe('Failed to update info file', e, s);
      return false;
    }
  }

  InfoItem? extractInfoFromFile(EnteFile file) {
    try {
      final infoData = file.pubMagicMetadata.info;
      if (infoData == null) {
        return null;
      }

      final typeString = infoData['type'] as String?;
      final data = infoData['data'] as Map<String, dynamic>?;

      if (typeString == null || data == null) {
        return null;
      }

      if (file.fileType != FileType.info) {
        file.fileType = FileType.info;
      }

      final infoType = InfoTypeExtension.fromString(typeString);

      InfoData infoDataObj;
      switch (infoType) {
        case InfoType.note:
          infoDataObj = PersonalNoteData.fromJson(data);
          break;
        case InfoType.physicalRecord:
          infoDataObj = PhysicalRecordData.fromJson(data);
          break;
        case InfoType.accountCredential:
          infoDataObj = AccountCredentialData.fromJson(data);
          break;
        case InfoType.emergencyContact:
          infoDataObj = EmergencyContactData.fromJson(data);
          break;
      }

      return InfoItem(
        type: infoType,
        data: infoDataObj,
        createdAt: DateTime.now(),
      );
    } catch (e, s) {
      _logger.severe('Failed to extract info from file', e, s);
      return null;
    }
  }

  bool isInfoFile(EnteFile file) {
    if (file.fileType == FileType.info) {
      return true;
    }
    if (file.fileType != null && file.fileType != FileType.other) {
      return false;
    }
    return file.pubMagicMetadata.info != null;
  }

  String getInfoFileTitle(InfoItem infoItem) {
    switch (infoItem.type) {
      case InfoType.note:
        final noteData = infoItem.data as PersonalNoteData;
        return noteData.title.isNotEmpty ? noteData.title : 'Note';
      case InfoType.physicalRecord:
        final recordData = infoItem.data as PhysicalRecordData;
        return recordData.name.isNotEmpty ? recordData.name : 'Location';
      case InfoType.accountCredential:
        final credData = infoItem.data as AccountCredentialData;
        return credData.name.isNotEmpty ? credData.name : 'Secret';
      case InfoType.emergencyContact:
        final contactData = infoItem.data as EmergencyContactData;
        return contactData.name.isNotEmpty
            ? contactData.name
            : 'Emergency Contact';
    }
  }

  String? getFileTitleFromFile(EnteFile file) {
    final infoItem = extractInfoFromFile(file);
    return infoItem != null ? getInfoFileTitle(infoItem) : null;
  }

  Future<EnteFile> _uploadInfoFile(
    EnteFile enteFile,
    Collection collection,
  ) async {
    return await FileUploader.instance.uploadInfoFile(enteFile, collection);
  }
}
