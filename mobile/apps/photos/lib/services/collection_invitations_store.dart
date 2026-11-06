import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:photos/models/collection/collection_invitation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:synchronized/synchronized.dart';

typedef InvitationDecoder =
    CollectionInvitation Function(Map<String, dynamic> json);

class CollectionInvitationsStore extends ChangeNotifier {
  final _logger = Logger('CollectionInvitationsStore');
  final _writes = Lock();
  SharedPreferences? _prefs;
  int? _accountID;
  InvitationDecoder? _decode;
  int _generation = 0;
  List<CollectionInvitation> _pending = const [];
  List<Map<String, dynamic>> _raw = const [];
  Set<String> _seen = {};

  List<CollectionInvitation> get pending => _pending;
  bool get hasUnseen =>
      _pending.any((item) => !_seen.contains(item.occurrenceKey));
  int? get accountID => _accountID;
  int get generation => _generation;

  String _key(int accountID) => 'collection_invitations_v1_$accountID';

  Future<void> initialize(
    SharedPreferences preferences,
    int? accountID, {
    required InvitationDecoder decode,
  }) async {
    _generation++;
    _prefs = preferences;
    _accountID = accountID;
    _decode = decode;
    _pending = const [];
    _raw = const [];
    _seen = {};
    final saved = accountID == null
        ? null
        : preferences.getString(_key(accountID));
    if (saved != null) {
      try {
        final json = jsonDecode(saved) as Map<String, dynamic>;
        final parsed = _parse(json['pending']);
        _raw = parsed.raw;
        _pending = parsed.pending;
        _seen = (json['seen'] as List).cast<String>().toSet();
      } catch (error, stack) {
        _raw = const [];
        _pending = const [];
        _seen = {};
        _logger.warning('Could not load cached invitations', error, stack);
      }
    }
    notifyListeners();
  }

  Future<List<CollectionInvitation>?> applySnapshot(
    Object? snapshot, {
    int? expectedGeneration,
  }) {
    final generation = expectedGeneration ?? _generation;
    return _writes.synchronized(() async {
      if (snapshot == null || _accountID == null || generation != _generation) {
        return null;
      }
      final parsed = _parse(snapshot);
      final occurrences = parsed.pending
          .map((item) => item.occurrenceKey)
          .toSet();
      final seen = _seen.intersection(occurrences);
      await _save(parsed.raw, seen);
      if (generation != _generation) return null;
      _raw = parsed.raw;
      _pending = parsed.pending;
      _seen = seen;
      notifyListeners();
      return _pending;
    });
  }

  Future<void> markSeen(Iterable<CollectionInvitation> snapshot) {
    final generation = _generation;
    final loaded = snapshot.map((item) => item.occurrenceKey).toSet();
    return _writes.synchronized(() async {
      if (_accountID == null || generation != _generation) return;
      final current = _pending.map((item) => item.occurrenceKey).toSet();
      final seen = _seen.union(loaded.intersection(current));
      if (setEquals(seen, _seen)) return;
      await _save(_raw, seen);
      if (generation != _generation) return;
      _seen = seen;
      notifyListeners();
    });
  }

  Future<void> removeAccepted(
    Iterable<int> collectionIDs, {
    int? expectedGeneration,
  }) {
    final generation = expectedGeneration ?? _generation;
    final ids = collectionIDs.toSet();
    return _writes.synchronized(() async {
      if (_accountID == null || generation != _generation) return;
      final raw = _raw
          .where((item) => !ids.contains(item['collectionID']))
          .toList();
      final pending = _pending
          .where((item) => !ids.contains(item.collectionID))
          .toList();
      final seen = _seen.intersection(
        pending.map((item) => item.occurrenceKey).toSet(),
      );
      await _save(raw, seen);
      if (generation != _generation) return;
      _raw = raw;
      _pending = List.unmodifiable(pending);
      _seen = seen;
      notifyListeners();
    });
  }

  Future<void> clearAccount() {
    final preferences = _prefs;
    final accountID = _accountID;
    _generation++;
    _accountID = null;
    _raw = const [];
    _pending = const [];
    _seen = {};
    notifyListeners();
    return _writes.synchronized(() async {
      if (accountID != null) await preferences?.remove(_key(accountID));
    });
  }

  ({List<Map<String, dynamic>> raw, List<CollectionInvitation> pending}) _parse(
    Object? value,
  ) {
    if (value is! List) {
      throw const FormatException('Incomplete invitation snapshot');
    }
    final raw = <Map<String, dynamic>>[];
    final pending = <CollectionInvitation>[];
    for (final item in value) {
      try {
        final json = Map<String, dynamic>.from(item as Map);
        final invitation = _decode!(json);
        raw.add(json);
        pending.add(invitation);
      } catch (error, stack) {
        final id = item is Map ? item['collectionID'] : null;
        // Parsing exceptions can include invitation content in their source.
        _logger.severe(
          'Could not decode collection invitation${id is int && id > 0 ? ' $id' : ''}',
          FormatException('Invalid invitation preview (${error.runtimeType})'),
          stack,
        );
      }
    }
    if (pending.map((item) => item.collectionID).toSet().length !=
        pending.length) {
      throw const FormatException('Duplicate invitations in snapshot');
    }
    pending.sort((a, b) {
      final timeOrder = b.sharedAt.compareTo(a.sharedAt);
      return timeOrder != 0
          ? timeOrder
          : b.collectionID.compareTo(a.collectionID);
    });
    return (raw: raw, pending: List.unmodifiable(pending));
  }

  Future<void> _save(List<Map<String, dynamic>> raw, Set<String> seen) async {
    final saved = await _prefs!.setString(
      _key(_accountID!),
      jsonEncode({'pending': raw, 'seen': seen.toList()}),
    );
    if (!saved) throw StateError('Could not save invitation state');
  }
}
