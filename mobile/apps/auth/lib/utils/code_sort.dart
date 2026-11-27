import 'package:ente_auth/models/code.dart';
import 'package:ente_auth/services/preference_service.dart';
import 'package:ente_pure_utils/ente_pure_utils.dart';

void sortAuthCodes(List<Code> codes, CodeSortKey sortKey) {
  switch (sortKey) {
    case CodeSortKey.issuerName:
      codes.sort((a, b) => compareNames(a.issuer, b.issuer));
      break;
    case CodeSortKey.accountName:
      codes.sort((a, b) => compareNames(a.account, b.account));
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

int _compareNewestFirst(Code a, Code b) {
  final byCreatedAt = (b.createdAt ?? 0).compareTo(a.createdAt ?? 0);
  if (byCreatedAt != 0) {
    return byCreatedAt;
  }
  return (b.generatedID ?? 0).compareTo(a.generatedID ?? 0);
}
