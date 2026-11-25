import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:ente_crypto/ente_crypto.dart';
import 'package:logging/logging.dart';
import 'package:photos/core/configuration.dart';
import 'package:photos/core/network/endpoint_config.dart';
import 'package:photos/models/collection/collection.dart';
import 'package:photos/models/file/file.dart';
import 'package:photos/models/metadata/file_magic.dart';
import 'package:photos/service_locator.dart';
import 'package:photos/utils/file_key.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PendingUpload {
  PendingUpload(this.file, this.createdAt);

  final EnteFile file;
  final int createdAt;
}

bool isPendingRow(Map<String, dynamic> row) =>
    row['isDeleted'] != true && row['moderationStatus'] == 'PENDING';

int _addedAt(Map<String, dynamic> row) => row['collectionAddedAt'] as int? ?? 0;

class PendingUploadsService {
  PendingUploadsService(this._dio, this._prefs);

  static const submitBatchSize = 1000;

  static PendingUploadsService get instance =>
      _instance ??= PendingUploadsService(
        ServiceLocator.instance.enteDio,
        ServiceLocator.instance.prefs,
      );
  static PendingUploadsService? _instance;

  final _logger = Logger('PendingUploadsService');
  final Dio _dio;
  final SharedPreferences _prefs;

  String _key(int collectionID, String part) =>
      'pending_uploads_${EndpointConfig(_prefs).endpoint}_${Configuration.instance.getUserID()}_${collectionID}_$part';

  final Map<int, Map<int, Map<String, dynamic>>> _rows = {};
  final Set<int> _loaded = {};
  Object? _account;

  Object get session => (
    EndpointConfig(_prefs).endpoint,
    Configuration.instance.getUserID(),
    Configuration.instance.getToken(),
  );

  void _resetOnAccountChange() {
    final account = session;
    if (account == _account) return;
    _rows.clear();
    _loaded.clear();
    _account = account;
  }

  Map<int, Map<String, dynamic>> _store(int collectionID) {
    _resetOnAccountChange();
    return _rows.putIfAbsent(collectionID, () => {});
  }

  void _apply(Map<int, Map<String, dynamic>> rows, List<dynamic> diff) {
    for (final value in diff) {
      final row = Map<String, dynamic>.from(value as Map);
      if (isPendingRow(row)) {
        rows[row['id'] as int] = row;
      } else {
        rows.remove(row['id'] as int);
      }
    }
  }

  int count(int collectionID) => _store(collectionID).length;

  Future<int> loadedCount(int collectionID) async {
    _resetOnAccountChange();
    if (!_loaded.contains(collectionID)) await resync(collectionID);
    return count(collectionID);
  }

  bool showsShield(Collection collection) =>
      collection.publicURLs.any((url) => url.requireApproval) ||
      count(collection.id) > 0;

  void applyDiff(int collectionID, List<dynamic> diff, Object fetchSession) {
    if (fetchSession != session) return;
    _apply(_store(collectionID), diff);
  }

  Future<void> resync(int collectionID) async {
    final fetchSession = session;
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
      if (fetchSession != session) return;
      final diff = response.data['diff'] as List<dynamic>;
      hasMore = response.data['hasMore'] as bool;
      _apply(rows, diff);
      for (final row in diff) {
        final updated = (row as Map)['updationTime'] as int;
        if (updated > sinceTime) sinceTime = updated;
      }
    } while (hasMore);
    _resetOnAccountChange();
    _rows[collectionID] = rows;
    _loaded.add(collectionID);
  }

  ReviewQueue reviewQueue(int collectionID) {
    final stored = _prefs.getString(_key(collectionID, 'choices'));
    if (stored == null) return ReviewQueue();
    return ReviewQueue.fromJson(
      Map<String, dynamic>.from(jsonDecode(stored) as Map),
    );
  }

  Future<void> saveReviewQueue(int collectionID, ReviewQueue queue) => _prefs
      .setString(_key(collectionID, 'choices'), jsonEncode(queue.toJson()));

  Future<List<PendingUpload>> files(int collectionID) async {
    _resetOnAccountChange();
    if (!_loaded.contains(collectionID)) await resync(collectionID);
    final result = <PendingUpload>[];
    for (final row in _store(collectionID).values.toList()) {
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
    final submitSession = session;
    await _dio.post(
      '/collections/pending-files/$action',
      data: {'collectionID': collectionID, 'fileIDs': ids},
    );
    if (submitSession == session) ids.forEach(_store(collectionID).remove);
  }
}

enum ReviewChoice { approve, reject }

class ReviewQueue {
  ReviewQueue([Map<int, ReviewChoice>? initial])
    : choices = initial ?? <int, ReviewChoice>{};

  final Map<int, ReviewChoice> choices;
  final List<(int, ReviewChoice?)> _history = [];

  factory ReviewQueue.fromJson(Map<String, dynamic> value) {
    final choices = Map<String, dynamic>.from(value['choices'] as Map);
    final queue = ReviewQueue({
      for (final entry in choices.entries)
        int.parse(entry.key): ReviewChoice.values.byName(entry.value as String),
    });
    for (final item in value['history'] as List<dynamic>) {
      final row = item as List<dynamic>;
      queue._history.add((
        row[0] as int,
        row[1] == null ? null : ReviewChoice.values.byName(row[1] as String),
      ));
    }
    return queue;
  }

  Map<String, dynamic> toJson() => {
    'choices': {
      for (final entry in choices.entries)
        entry.key.toString(): entry.value.name,
    },
    'history': [
      for (final entry in _history) [entry.$1, entry.$2?.name],
    ],
  };

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
