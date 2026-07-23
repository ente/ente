import 'dart:convert';
import 'dart:math';

import 'package:ente_crypto/ente_crypto.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:photos/core/configuration.dart';
import 'package:photos/db/files_db.dart';
import 'package:photos/generated/l10n.dart';
import 'package:photos/models/file/extensions/file_props.dart';
import 'package:photos/models/file/file.dart';
import "package:photos/models/metadata/file_magic.dart";
import "package:photos/service_locator.dart";
import "package:photos/services/collections_service.dart";
import "package:photos/utils/dialog_util.dart";
import "package:photos/utils/file_key.dart";

class DiffFetcher {
  final _logger = Logger("DiffFetcher");

  Future<List<EnteFile>> getPublicFiles(
    BuildContext context,
    int collectionID,
    bool sortAsc,
  ) async {
    try {
      bool hasMore = false;
      final sharedFiles = <EnteFile>[];
      final headers = CollectionsService.instance.publicCollectionHeaders(
        collectionID,
      );
      final collectionKey = CollectionsService.instance.getPublicCollectionKey(
        collectionID,
      );
      int sinceTime = 0;

      do {
        final responseData = await collectionShareGateway.getPublicDiff(
          headers: headers,
          sinceTime: sinceTime,
        );

        final diff = responseData["diff"] as List;
        hasMore = responseData["hasMore"] as bool;

        for (final item in diff) {
          final file = EnteFile();
          if (item["isDeleted"]) {
            continue;
          }
          file.uploadedFileID = item["id"];
          file.collectionID = item["collectionID"];
          file.ownerID = item["ownerID"];
          file.encryptedKey = item["encryptedKey"];
          file.keyDecryptionNonce = item["keyDecryptionNonce"];
          final collectionAddedAt = item["collectionAddedAt"];
          if (collectionAddedAt != null) {
            file.addedTime = collectionAddedAt as int;
          }
          file.fileDecryptionHeader = item["file"]["decryptionHeader"];
          file.thumbnailDecryptionHeader =
              item["thumbnail"]["decryptionHeader"];
          file.metadataDecryptionHeader = item["metadata"]["decryptionHeader"];
          if (item["info"] != null) {
            file.fileSize = item["info"]["fileSize"];
          }
          final fileKey = getFileKeyWithCollectionKey(file, collectionKey);
          final encodedMetadata = await CryptoUtil.decryptChaCha(
            CryptoUtil.base642bin(item["metadata"]["encryptedData"]),
            fileKey,
            CryptoUtil.base642bin(file.metadataDecryptionHeader!),
          );
          final Map<String, dynamic> metadata = jsonDecode(
            utf8.decode(encodedMetadata),
          );
          file.applyMetadata(metadata);
          if (item['pubMagicMetadata'] != null) {
            final utfEncodedMmd = await CryptoUtil.decryptChaCha(
              CryptoUtil.base642bin(item['pubMagicMetadata']['data']),
              fileKey,
              CryptoUtil.base642bin(item['pubMagicMetadata']['header']),
            );
            file.pubMmdEncodedJson = utf8.decode(utfEncodedMmd);
            file.pubMmdVersion = item['pubMagicMetadata']['version'];
            file.pubMagicMetadata = PubMagicMetadata.fromEncodedJson(
              file.pubMmdEncodedJson!,
            );
          }

          // To avoid local file to be used as thumbnail or full file.
          file.localID = null;

          sharedFiles.add(file);
        }

        if (diff.isNotEmpty) {
          sinceTime = diff.last["updationTime"];
        }
      } while (hasMore);
      if (sortAsc) {
        sharedFiles.sort((a, b) => a.creationTime!.compareTo(b.creationTime!));
      }
      return sharedFiles;
    } catch (e, s) {
      _logger.severe("Failed to decrypt collection ", e, s);
      if (context.mounted) {
        await showErrorDialog(
          context,
          AppLocalizations.of(context).somethingWentWrong,
          e.toString(),
        );
      }
      rethrow;
    }
  }

  Future<Diff> getEncryptedFilesDiff(int collectionID, int sinceTime) async {
    try {
      final response = await collectionsGateway.getDiff(
        collectionID: collectionID,
        sinceTime: sinceTime,
      );
      int latestUpdatedAtTime = 0;
      final diff = response["diff"] as List;
      final bool hasMore = response["hasMore"] as bool;
      final startTime = DateTime.now();
      final currentUserID = Configuration.instance.getUserID();
      late Set<int> existingUploadIDs;
      if (diff.isNotEmpty) {
        existingUploadIDs = await FilesDB.instance.getUploadedFileIDs(
          collectionID,
        );
      }
      final deletedFiles = <EnteFile>[];
      final updatedFiles = <EnteFile>[];
      final ownCollectCandidatesByUploadID =
          <int, List<_OwnCollectCandidate>>{};

      for (final item in diff) {
        final file = EnteFile();
        file.uploadedFileID = item["id"];
        file.collectionID = item["collectionID"];
        file.updationTime = item["updationTime"];
        latestUpdatedAtTime = max(latestUpdatedAtTime, file.updationTime!);

        if (item["isDeleted"]) {
          if (existingUploadIDs.contains(file.uploadedFileID)) {
            deletedFiles.add(file);
          }
          continue;
        }
        if (existingUploadIDs.contains(file.uploadedFileID)) {
          final existingFile = await FilesDB.instance.getUploadedFile(
            file.uploadedFileID!,
            file.collectionID!,
          );
          if (existingFile != null) {
            file.generatedID = existingFile.generatedID;
          }
        }
        file.ownerID = item["ownerID"];
        file.encryptedKey = item["encryptedKey"];
        file.keyDecryptionNonce = item["keyDecryptionNonce"];
        final collectionAddedAt = item["collectionAddedAt"] as int?;
        file.fileDecryptionHeader = item["file"]["decryptionHeader"];
        file.thumbnailDecryptionHeader = item["thumbnail"]["decryptionHeader"];
        file.metadataDecryptionHeader = item["metadata"]["decryptionHeader"];
        if (item["info"] != null) {
          file.fileSize = item["info"]["fileSize"];
        }
        final fileKey = getFileKey(file);
        final encodedMetadata = await CryptoUtil.decryptChaCha(
          CryptoUtil.base642bin(item["metadata"]["encryptedData"]),
          fileKey,
          CryptoUtil.base642bin(file.metadataDecryptionHeader!),
        );
        final Map<String, dynamic> metadata = jsonDecode(
          utf8.decode(encodedMetadata),
        );
        file.applyMetadata(metadata);
        if (item['magicMetadata'] != null) {
          final utfEncodedMmd = await CryptoUtil.decryptChaCha(
            CryptoUtil.base642bin(item['magicMetadata']['data']),
            fileKey,
            CryptoUtil.base642bin(item['magicMetadata']['header']),
          );
          file.mMdEncodedJson = utf8.decode(utfEncodedMmd);
          file.mMdVersion = item['magicMetadata']['version'];
          file.magicMetadata = MagicMetadata.fromEncodedJson(
            file.mMdEncodedJson!,
          );
        }
        if (item['pubMagicMetadata'] != null) {
          final utfEncodedMmd = await CryptoUtil.decryptChaCha(
            CryptoUtil.base642bin(item['pubMagicMetadata']['data']),
            fileKey,
            CryptoUtil.base642bin(item['pubMagicMetadata']['header']),
          );
          file.pubMmdEncodedJson = utf8.decode(utfEncodedMmd);
          file.pubMmdVersion = item['pubMagicMetadata']['version'];
          file.pubMagicMetadata = PubMagicMetadata.fromEncodedJson(
            file.pubMmdEncodedJson!,
          );
        }
        if (collectionAddedAt != null && collectionAddedAt > 0) {
          final isShared =
              currentUserID != null && file.ownerID != currentUserID;
          final isOwnCollect =
              currentUserID != null &&
              file.ownerID == currentUserID &&
              file.isCollect;
          if (isShared) {
            file.addedTime = collectionAddedAt;
          } else if (isOwnCollect) {
            file.addedTime = collectionAddedAt;
            ownCollectCandidatesByUploadID
                .putIfAbsent(
                  file.uploadedFileID!,
                  () => <_OwnCollectCandidate>[],
                )
                .add(
                  _OwnCollectCandidate(
                    file: file,
                    collectionAddedAt: collectionAddedAt,
                  ),
                );
          } else {
            file.addedTime = -1;
          }
        } else {
          file.addedTime = -1;
        }
        updatedFiles.add(file);
      }

      if (currentUserID != null) {
        await _reconcileOwnCollectAddedTime(
          collectionID: collectionID,
          currentUserID: currentUserID,
          ownCollectCandidatesByUploadID: ownCollectCandidatesByUploadID,
        );
      }

      _logger.info(
        '[Collection-$collectionID] parsed ${diff.length} '
        'diff items ( ${updatedFiles.length} updated) in ${DateTime.now().difference(startTime).inMilliseconds}ms',
      );
      return Diff(updatedFiles, deletedFiles, hasMore, latestUpdatedAtTime);
    } catch (e, s) {
      _logger.severe("Failed to parse collection diff", e, s);
      rethrow;
    }
  }

  Future<void> _reconcileOwnCollectAddedTime({
    required int collectionID,
    required int currentUserID,
    required Map<int, List<_OwnCollectCandidate>>
    ownCollectCandidatesByUploadID,
  }) async {
    if (ownCollectCandidatesByUploadID.isEmpty) {
      return;
    }

    final incomingMinByUploadID = <int, int>{};
    for (final entry in ownCollectCandidatesByUploadID.entries) {
      final minIncoming = entry.value
          .map((candidate) => candidate.collectionAddedAt)
          .reduce(min);
      incomingMinByUploadID[entry.key] = minIncoming;
    }

    final dbMinByUploadID = await FilesDB.instance
        .getMinPositiveAddedTimeForUploadedFiles(
          incomingMinByUploadID.keys.toSet(),
          currentUserID,
        );

    var collectCandidatesCount = 0;
    var keptIncomingCount = 0;
    var suppressedIncomingCount = 0;
    final uploadsToReset = <int>{};

    for (final entry in ownCollectCandidatesByUploadID.entries) {
      final uploadedFileID = entry.key;
      final candidates = entry.value;
      collectCandidatesCount += candidates.length;
      final incomingMin = incomingMinByUploadID[uploadedFileID]!;
      final dbMin = dbMinByUploadID[uploadedFileID];

      if (dbMin != null && dbMin <= incomingMin) {
        for (final candidate in candidates) {
          candidate.file.addedTime = -1;
        }
        suppressedIncomingCount += candidates.length;
        continue;
      }

      if (dbMin != null && dbMin > incomingMin) {
        uploadsToReset.add(uploadedFileID);
      }

      var keptForUploadID = false;
      for (final candidate in candidates) {
        if (!keptForUploadID && candidate.collectionAddedAt == incomingMin) {
          candidate.file.addedTime = incomingMin;
          keptForUploadID = true;
          keptIncomingCount++;
        } else {
          candidate.file.addedTime = -1;
          suppressedIncomingCount++;
        }
      }
    }

    if (uploadsToReset.isNotEmpty) {
      await FilesDB.instance.resetPositiveAddedTimeForUploadedFiles(
        uploadsToReset,
        currentUserID,
      );
    }

    _logger.info(
      '[Collection-$collectionID] own_collect_added_time_reconcile '
      'candidates=$collectCandidatesCount '
      'uploads=${ownCollectCandidatesByUploadID.length} '
      'kept=$keptIncomingCount suppressed=$suppressedIncomingCount '
      'dbResets=${uploadsToReset.length}',
    );
  }
}

class Diff {
  final List<EnteFile> updatedFiles;
  final List<EnteFile> deletedFiles;
  final bool hasMore;
  final int latestUpdatedAtTime;

  Diff(
    this.updatedFiles,
    this.deletedFiles,
    this.hasMore,
    this.latestUpdatedAtTime,
  );
}

class _OwnCollectCandidate {
  final EnteFile file;
  final int collectionAddedAt;

  const _OwnCollectCandidate({
    required this.file,
    required this.collectionAddedAt,
  });
}
