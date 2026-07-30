import "package:collection/collection.dart";
import "package:photos/models/search/generic_search_result.dart";
import "package:photos/models/search/search_constants.dart";
import "package:photos/settings/local_settings.dart";

class PeopleSortConfig {
  final PeopleSortKey sortKey;
  final bool nameSortAscending;
  final bool updatedSortAscending;
  final bool photosSortAscending;

  const PeopleSortConfig({
    required this.sortKey,
    required this.nameSortAscending,
    required this.updatedSortAscending,
    required this.photosSortAscending,
  });
}

void sortPeopleFaces(List<GenericSearchResult> faces, PeopleSortConfig config) {
  if (faces.isEmpty) {
    return;
  }

  final latestTimes = <GenericSearchResult, int>{};
  if (config.sortKey == PeopleSortKey.lastUpdated) {
    for (final face in faces) {
      latestTimes[face] = _latestAssignedTime(face);
    }
  }

  faces.sort((a, b) {
    final aHasPerson = _hasPersonId(a);
    final bHasPerson = _hasPersonId(b);
    if (aHasPerson != bHasPerson) {
      return aHasPerson ? -1 : 1;
    }

    final bool aPinned = a.params[kPersonPinned] as bool? ?? false;
    final bool bPinned = b.params[kPersonPinned] as bool? ?? false;
    if (aPinned != bPinned) {
      return aPinned ? -1 : 1;
    }

    int compareValue;
    switch (config.sortKey) {
      case PeopleSortKey.mostPhotos:
        compareValue = a.fileCount().compareTo(b.fileCount());
        if (!config.photosSortAscending) {
          compareValue = -compareValue;
        }
        break;
      case PeopleSortKey.name:
        if (!aHasPerson) {
          compareValue = b.fileCount().compareTo(a.fileCount());
        } else {
          compareValue = compareAsciiLowerCaseNatural(a.name(), b.name());
          if (!config.nameSortAscending) {
            compareValue = -compareValue;
          }
        }
        break;
      case PeopleSortKey.lastUpdated:
        final aTime = latestTimes[a] ?? 0;
        final bTime = latestTimes[b] ?? 0;
        compareValue = aTime.compareTo(bTime);
        if (!config.updatedSortAscending) {
          compareValue = -compareValue;
        }
        break;
    }

    if (compareValue != 0) {
      return compareValue;
    }
    return compareAsciiLowerCaseNatural(a.name(), b.name());
  });
}

bool _hasPersonId(GenericSearchResult face) {
  final personId = face.params[kPersonParamID] as String?;
  return personId != null && personId.isNotEmpty;
}

int _latestAssignedTime(GenericSearchResult face) {
  var latestTime = 0;
  for (final file in face.resultFiles()) {
    int creationTime = 0;
    if (file.creationTime != null && file.creationTime! > 0) {
      creationTime = file.creationTime!;
    }
    if (creationTime > latestTime) {
      latestTime = creationTime;
    }
  }
  return latestTime;
}
