import 'dart:convert';
import 'dart:typed_data';

import "package:ente_crypto_api/ente_crypto_api.dart";
import 'package:locker/models/file_type.dart';
import 'package:locker/services/db/locker_db.dart';
import 'package:locker/services/trash/models/trash_file.dart';
import 'package:locker/utils/crypto_helper.dart';
import 'package:sqflite/sqflite.dart';

const int _trashPayloadVersion = 1;

extension TrashTable on LockerDB {
  Future<void> insertTrashFiles(List<TrashFile> trashFiles) async {
    final batch = database.batch();

    for (final trashFile in trashFiles) {
      final map = await _trashFileToMap(this, trashFile);
      batch.insert(
        LockerDB.trashTable,
        map,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    await batch.commit();
  }

  Future<void> deleteTrashFiles(List<int> uploadedFileIDs) async {
    final batch = database.batch();

    for (final uploadedFileID in uploadedFileIDs) {
      batch.delete(
        LockerDB.trashTable,
        where: 'uploaded_file_id = ?',
        whereArgs: [uploadedFileID],
      );
    }

    await batch.commit();
  }

  Future<List<TrashFile>> getTrashFiles() async {
    final rows = await database.query(LockerDB.trashTable);
    final files = <TrashFile>[];
    for (final row in rows) {
      files.add(await _trashFileFromRow(this, row));
    }
    return files;
  }

  Future<void> clearTrashFilesTable() async {
    await database.delete(LockerDB.trashTable);
  }
}

Future<Map<String, dynamic>> _trashFileToMap(
  LockerDB db,
  TrashFile trashFile,
) async {
  final fileKey = await _getTrashFileKey(db, trashFile);
  final encryptedPayload = await CryptoUtil.encryptData(
    utf8.encode(jsonEncode(_trashPayloadToMap(trashFile))),
    fileKey,
  );

  return {
    'uploaded_file_id': trashFile.uploadedFileID!,
    'collection_id': trashFile.collectionID,
    'owner_id': trashFile.ownerID,
    'updation_time': trashFile.updationTime,
    'encrypted_key': trashFile.encryptedKey,
    'key_decryption_nonce': trashFile.keyDecryptionNonce,
    'file_decryption_header': trashFile.fileDecryptionHeader,
    'thumbnail_decryption_header': trashFile.thumbnailDecryptionHeader,
    'metadata_decryption_header': trashFile.metadataDecryptionHeader,
    'file_size': trashFile.fileSize,
    'created_at': trashFile.createdAt,
    'update_at': trashFile.updateAt,
    'delete_by': trashFile.deleteBy,
    'payload_encrypted_data': CryptoUtil.bin2base64(
      encryptedPayload.encryptedData!,
    ),
    'payload_decryption_header': CryptoUtil.bin2base64(
      encryptedPayload.header!,
    ),
    'payload_version': _trashPayloadVersion,
  };
}

Map<String, dynamic> _trashPayloadToMap(TrashFile trashFile) {
  return {
    'local_path': trashFile.localPath,
    'title': trashFile.title,
    'file_type': trashFile.fileType != null
        ? getInt(trashFile.fileType!)
        : null,
    'creation_time': trashFile.creationTime,
    'modification_time': trashFile.modificationTime,
    'added_time': trashFile.addedTime,
    'hash': trashFile.hash,
    'metadata_version': trashFile.metadataVersion,
    'm_md_encoded_json': trashFile.mMdEncodedJson,
    'm_md_version': trashFile.mMdVersion,
    'pub_mmd_encoded_json': trashFile.pubMmdEncodedJson,
    'pub_mmd_version': trashFile.pubMmdVersion,
  };
}

Future<TrashFile> _trashFileFromRow(
  LockerDB db,
  Map<String, dynamic> row,
) async {
  final encryptedPayloadData = row['payload_encrypted_data'] as String?;
  final payloadDecryptionHeader = row['payload_decryption_header'] as String?;
  if (encryptedPayloadData == null || payloadDecryptionHeader == null) {
    throw Exception('Invalid trash_files row: missing encrypted payload');
  }

  final fileKey = await _getTrashFileKeyFromRow(db, row);
  final decryptedPayload = await CryptoUtil.decryptData(
    CryptoUtil.base642bin(encryptedPayloadData),
    fileKey,
    CryptoUtil.base642bin(payloadDecryptionHeader),
  );
  final payload = jsonDecode(utf8.decode(decryptedPayload));

  final trashFile = TrashFile();
  trashFile.uploadedFileID = row['uploaded_file_id'];
  trashFile.collectionID = row['collection_id'];
  trashFile.encryptedKey = row['encrypted_key'];
  trashFile.keyDecryptionNonce = row['key_decryption_nonce'];

  trashFile.localPath = payload['local_path'];
  trashFile.ownerID = row['owner_id'] ?? payload['owner_id'];
  trashFile.title = payload['title'];
  trashFile.creationTime = payload['creation_time'];
  trashFile.modificationTime = payload['modification_time'];
  trashFile.updationTime = row['updation_time'] ?? payload['updation_time'];
  trashFile.addedTime = payload['added_time'];
  trashFile.hash = payload['hash'];
  trashFile.metadataVersion = payload['metadata_version'];
  trashFile.fileDecryptionHeader =
      row['file_decryption_header'] ?? payload['file_decryption_header'];
  trashFile.thumbnailDecryptionHeader =
      row['thumbnail_decryption_header'] ??
      payload['thumbnail_decryption_header'];
  trashFile.metadataDecryptionHeader =
      row['metadata_decryption_header'] ??
      payload['metadata_decryption_header'];
  trashFile.fileSize = row['file_size'] ?? payload['file_size'];
  trashFile.mMdEncodedJson = payload['m_md_encoded_json'];
  trashFile.mMdVersion = payload['m_md_version'] ?? 0;
  trashFile.pubMmdEncodedJson = payload['pub_mmd_encoded_json'];
  trashFile.pubMmdVersion = payload['pub_mmd_version'] ?? 1;
  final fileTypeIndex = payload['file_type'] as int?;
  if (fileTypeIndex != null) {
    trashFile.fileType = getFileType(fileTypeIndex);
  } else if (trashFile.pubMagicMetadata.info != null) {
    trashFile.fileType = FileType.info;
  }
  trashFile.createdAt = row['created_at'] ?? payload['created_at'];
  trashFile.updateAt = row['update_at'] ?? payload['update_at'];
  trashFile.deleteBy = row['delete_by'] ?? payload['delete_by'];

  return trashFile;
}

Future<Uint8List> _getTrashFileKey(LockerDB db, TrashFile file) async {
  if (file.collectionID == null ||
      file.encryptedKey == null ||
      file.keyDecryptionNonce == null) {
    throw Exception(
      'Missing file key fields for trash file ${file.uploadedFileID}',
    );
  }

  final collection = await db.getCollection(file.collectionID!);
  final collectionKey = CryptoHelper.instance.getCollectionKey(collection);
  return CryptoHelper.instance.getFileKey(
    file.encryptedKey!,
    file.keyDecryptionNonce!,
    collectionKey,
  );
}

Future<Uint8List> _getTrashFileKeyFromRow(
  LockerDB db,
  Map<String, dynamic> row,
) async {
  final collectionID = row['collection_id'] as int?;
  final encryptedKey = row['encrypted_key'] as String?;
  final keyDecryptionNonce = row['key_decryption_nonce'] as String?;

  if (collectionID == null ||
      encryptedKey == null ||
      keyDecryptionNonce == null) {
    throw Exception(
      'Missing key fields in trash_files for file ${row['uploaded_file_id']}',
    );
  }

  final collection = await db.getCollection(collectionID);
  final collectionKey = CryptoHelper.instance.getCollectionKey(collection);
  return CryptoHelper.instance.getFileKey(
    encryptedKey,
    keyDecryptionNonce,
    collectionKey,
  );
}
