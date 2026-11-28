import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:ente_crypto/ente_crypto.dart';
import 'package:logging/logging.dart';
import 'package:photos/models/file/file.dart';
import 'package:photos/models/metadata/file_magic.dart';
import 'package:photos/service_locator.dart';
import 'package:photos/utils/file_key.dart';

class PendingUpload {
  PendingUpload(this.file, this.createdAt);

  final EnteFile file;
  final int createdAt;
}

bool _isPendingRow(Map<String, dynamic> row) =>
    row['isDeleted'] != true && row['moderationStatus'] == 'PENDING';

int _addedAt(Map<String, dynamic> row) => row['collectionAddedAt'] as int? ?? 0;

class PendingUploadsService {
  PendingUploadsService(this._dio);

  static const _submitBatchSize = 1000;

  static PendingUploadsService get instance =>
      _instance ??= PendingUploadsService(ServiceLocator.instance.enteDio);
  static PendingUploadsService? _instance;

  final _logger = Logger('PendingUploadsService');
  final Dio _dio;

  Future<List<PendingUpload>> load(int collectionID) async {
    final rows = <int, Map<String, dynamic>>{};
    var sinceTime = 0;
    bool hasMore;
    do {
      final response = await _dio.get(
        '/collections/v2/diff',
        queryParameters: {
          'collectionID': collectionID,
          'sinceTime': sinceTime,
          'includePending': true,
        },
      );
      final diff = response.data['diff'] as List<dynamic>;
      hasMore = response.data['hasMore'] as bool;
      for (final value in diff) {
        final row = Map<String, dynamic>.from(value as Map);
        if (_isPendingRow(row)) {
          rows[row['id'] as int] = row;
        } else {
          rows.remove(row['id'] as int);
        }
        final updated = row['updationTime'] as int;
        if (updated > sinceTime) sinceTime = updated;
      }
    } while (hasMore);
    return _decode(collectionID, rows.values);
  }

  Future<List<PendingUpload>> _decode(
    int collectionID,
    Iterable<Map<String, dynamic>> rows,
  ) async {
    final result = <PendingUpload>[];
    for (final row in rows) {
      try {
        final file = EnteFile()
          ..uploadedFileID = row['id'] as int
          ..collectionID = collectionID
          ..ownerID = row['ownerID'] as int
          ..encryptedKey = row['encryptedKey'] as String
          ..keyDecryptionNonce = row['keyDecryptionNonce'] as String
          ..fileDecryptionHeader = row['file']['decryptionHeader'] as String
          ..thumbnailDecryptionHeader =
              row['thumbnail']['decryptionHeader'] as String
          ..metadataDecryptionHeader =
              row['metadata']['decryptionHeader'] as String
          ..fileSize = row['info']?['fileSize'] as int?;
        final fileKey = getFileKey(file);
        final metadata = await CryptoUtil.decryptChaCha(
          CryptoUtil.base642bin(row['metadata']['encryptedData'] as String),
          fileKey,
          CryptoUtil.base642bin(file.metadataDecryptionHeader!),
        );
        file.applyMetadata(
          jsonDecode(utf8.decode(metadata)) as Map<String, dynamic>,
        );
        final publicMagic = row['pubMagicMetadata'];
        if (publicMagic != null) {
          final decoded = await CryptoUtil.decryptChaCha(
            CryptoUtil.base642bin(publicMagic['data'] as String),
            fileKey,
            CryptoUtil.base642bin(publicMagic['header'] as String),
          );
          file.pubMmdEncodedJson = utf8.decode(decoded);
          file.pubMmdVersion = publicMagic['version'] as int;
          file.pubMagicMetadata = PubMagicMetadata.fromEncodedJson(
            file.pubMmdEncodedJson!,
          );
        }
        result.add(PendingUpload(file, _addedAt(row)));
      } catch (error, stack) {
        _logger.warning(
          'Could not read pending upload ${row['id']}',
          error,
          stack,
        );
      }
    }
    result.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return result;
  }

  Future<void> submit(int collectionID, String action, List<int> ids) async {
    for (var start = 0; start < ids.length; start += _submitBatchSize) {
      await _dio.post(
        '/collections/pending-files/$action',
        data: {
          'collectionID': collectionID,
          'fileIDs': ids.skip(start).take(_submitBatchSize).toList(),
        },
      );
    }
  }
}

enum ReviewChoice { approve, reject }

class ReviewQueue {
  final Map<int, ReviewChoice> choices = {};
  final List<(int, ReviewChoice?)> _history = [];

  int get approveCount =>
      choices.values.where((choice) => choice == ReviewChoice.approve).length;
  int get rejectCount =>
      choices.values.where((choice) => choice == ReviewChoice.reject).length;

  void choose(int id, ReviewChoice choice) {
    _history.add((id, choices[id]));
    choices[id] = choice;
  }

  void undo() {
    if (_history.isEmpty) return;
    final (id, previous) = _history.removeLast();
    if (previous == null) {
      choices.remove(id);
    } else {
      choices[id] = previous;
    }
  }

  void remove(Iterable<int> ids) {
    for (final id in ids) {
      choices.remove(id);
    }
    _history.removeWhere((entry) => !choices.containsKey(entry.$1));
  }

  void retain(Iterable<int> liveIDs) {
    final live = liveIDs.toSet();
    choices.removeWhere((id, _) => !live.contains(id));
    _history.removeWhere((entry) => !live.contains(entry.$1));
  }
}
