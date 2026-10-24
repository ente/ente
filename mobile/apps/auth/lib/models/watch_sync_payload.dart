import 'package:collection/collection.dart';
import 'package:ente_auth/models/code.dart';
import 'package:ente_auth/services/preference_service.dart';
import 'package:ente_auth/utils/totp_util.dart';

class WatchSyncToken {
  const WatchSyncToken({
    required this.id,
    required this.issuer,
    required this.account,
    required this.secret,
    required this.algorithm,
    required this.digits,
    required this.period,
    required this.isFavorite,
    required this.sortOrder,
  });

  final String id;
  final String issuer;
  final String account;
  final String secret;
  final String algorithm;
  final int digits;
  final int period;
  final bool isFavorite;
  final int sortOrder;

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'issuer': issuer,
      'account': account,
      'secret': secret,
      'algorithm': algorithm,
      'digits': digits,
      'period': period,
      'isFavorite': isFavorite,
      'sortOrder': sortOrder,
    };
  }
}

class WatchSyncPayload {
  const WatchSyncPayload({
    required this.version,
    required this.timestamp,
    required this.syncType,
    required this.tokens,
    required this.deletedIds,
  });

  final int version;
  final int timestamp;
  final String syncType;
  final List<WatchSyncToken> tokens;
  final List<String> deletedIds;

  Map<String, Object?> toJson() {
    return {
      'version': version,
      'timestamp': timestamp,
      'syncType': syncType,
      'tokens': [for (final token in tokens) token.toJson()],
      'deletedIds': deletedIds,
    };
  }
}

/// Builds the version-1 watch context.
///
/// [deletedIds] is the caller's set (previous successful ids, plus any
/// explicit removals). Ids that are also in the resulting token list are
/// removed so one context never updates and deletes the same id. Codes with
/// a null [Code.generatedID] are omitted from both arrays; the secret is
/// never used as an id.
WatchSyncPayload buildWatchPayload(
  List<Code> codes, {
  required bool syncAll,
  required Set<String> deletedIds,
  CodeSortKey sortKey = CodeSortKey.issuerName,
  int? timestamp,
}) {
  final eligible = <Code>[
    for (final code in codes)
      if (_isEligible(code, syncAll: syncAll)) code,
  ];
  _sortEligibleCodes(eligible, sortKey);
  final tokens = <WatchSyncToken>[
    for (var index = 0; index < eligible.length; index++)
      WatchSyncToken(
        id: eligible[index].generatedID!.toString(),
        issuer: eligible[index].issuer,
        account: eligible[index].account,
        secret: getSanitizedSecret(eligible[index].secret),
        algorithm: eligible[index].algorithm.name.toUpperCase(),
        digits: eligible[index].digits,
        period: eligible[index].period,
        isFavorite: eligible[index].display.pinned,
        sortOrder: index,
      ),
  ];
  final tokenIds = <String>{for (final token in tokens) token.id};
  final filteredDeleted = <String>[
    for (final id in deletedIds)
      if (!tokenIds.contains(id)) id,
  ];
  return WatchSyncPayload(
    version: 1,
    timestamp: timestamp ?? DateTime.now().millisecondsSinceEpoch ~/ 1000,
    syncType: 'DELTA',
    tokens: tokens,
    deletedIds: filteredDeleted,
  );
}

/// Phase 1 has no "sync all accounts" control. The push and the
/// copy-to-iPhone lookup both use this flag so they cannot drift.
const bool watchSyncsAllAccounts = false;

/// True when [code] is part of the set Phase 1 sends to the watch.
///
/// Copy-to-iPhone uses the same predicate. An id that is not pinned or
/// tagged `#watch`, or that is trashed, Steam, or HOTP, does not produce
/// an OTP for the watch.
bool isEligibleForWatchSync(Code code) {
  return _isEligible(code, syncAll: watchSyncsAllAccounts);
}

bool _isEligible(Code code, {required bool syncAll}) {
  if (code.hasError) {
    return false;
  }
  if (code.generatedID == null) {
    return false;
  }
  if (code.isTrashed) {
    return false;
  }
  if (code.type == Type.hotp) {
    return false;
  }
  if (code.type == Type.steam || code.issuer.toLowerCase() == 'steam') {
    return false;
  }
  if (syncAll) {
    return true;
  }
  return code.isPinned || _hasWatchTag(code);
}

bool _hasWatchTag(Code code) {
  for (final tag in code.display.tags) {
    if (tag.trim() == '#watch') {
      return true;
    }
  }
  return false;
}

/// Home-screen order: pinned codes move to the front for every key except
/// [CodeSortKey.manual].
void _sortEligibleCodes(List<Code> codes, CodeSortKey sortKey) {
  switch (sortKey) {
    case CodeSortKey.issuerName:
      codes.sort((a, b) => compareAsciiLowerCaseNatural(a.issuer, b.issuer));
      break;
    case CodeSortKey.accountName:
      codes.sort(
        (a, b) => compareAsciiLowerCaseNatural(a.account, b.account),
      );
      break;
    case CodeSortKey.mostFrequentlyUsed:
      codes.sort((a, b) => b.display.tapCount.compareTo(a.display.tapCount));
      break;
    case CodeSortKey.recentlyUsed:
      codes.sort(
        (a, b) => b.display.lastUsedAt.compareTo(a.display.lastUsedAt),
      );
      break;
    case CodeSortKey.manual:
      codes.sort((a, b) => a.display.position.compareTo(b.display.position));
      break;
    case CodeSortKey.newestFirst:
      codes.sort(_compareNewestFirst);
      break;
  }
  if (sortKey != CodeSortKey.manual) {
    int insertIndex = 0;
    for (int i = 0; i < codes.length; i++) {
      if (codes[i].isPinned) {
        final code = codes.removeAt(i);
        codes.insert(insertIndex, code);
        insertIndex++;
      }
    }
  }
}

/// Descending [Code.createdAt], then descending [Code.generatedID].
/// A null `createdAt` sorts last. HomePage assumes both timestamps exist.
int _compareNewestFirst(Code a, Code b) {
  final aCreated = a.createdAt;
  final bCreated = b.createdAt;
  if (aCreated == null || bCreated == null) {
    if (aCreated == null && bCreated == null) {
      return _compareGeneratedIdDesc(a, b);
    }
    return aCreated == null ? 1 : -1;
  }
  final byCreatedAt = bCreated.compareTo(aCreated);
  if (byCreatedAt != 0) {
    return byCreatedAt;
  }
  return _compareGeneratedIdDesc(a, b);
}

int _compareGeneratedIdDesc(Code a, Code b) {
  final aId = a.generatedID;
  final bId = b.generatedID;
  if (aId == null && bId == null) {
    return 0;
  }
  if (aId == null) {
    return 1;
  }
  if (bId == null) {
    return -1;
  }
  return bId.compareTo(aId);
}
