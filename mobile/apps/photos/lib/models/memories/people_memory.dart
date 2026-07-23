import "dart:async";

import "package:photos/generated/l10n.dart";
import "package:photos/models/memories/memory.dart";
import "package:photos/models/memories/smart_memory.dart";

enum PeopleMemoryType {
  youAndThem,
  doingSomethingTogether,
  spotlight,
  lastTimeYouSawThem,
}

const peopleRotationTypes = [
  PeopleMemoryType.youAndThem,
  PeopleMemoryType.doingSomethingTogether,
  PeopleMemoryType.spotlight,
];

PeopleMemoryType peopleMemoryTypeFromString(String type) {
  switch (type) {
    case "youAndThem":
      return PeopleMemoryType.youAndThem;
    case "doingSomethingTogether":
      return PeopleMemoryType.doingSomethingTogether;
    case "spotlight":
      return PeopleMemoryType.spotlight;
    case "lastTimeYouSawThem":
      return PeopleMemoryType.lastTimeYouSawThem;
    default:
      throw ArgumentError("Invalid people memory type: $type");
  }
}

enum PeopleActivity {
  admiring,
  embracing,
  party,
  hiking,
  feast,
  selfies,
  posing,
  background,
  sports,
  roadtrip,
}

String activityQuery(PeopleActivity activity) {
  switch (activity) {
    case PeopleActivity.admiring:
      return "Photo of two people admiring or looking at each other in a loving but non-intimate and non-physical way";
    case PeopleActivity.embracing:
      return "Photo of people hugging or embracing each other lovingly, without inappropriately kissing or other intimate actions";
    case PeopleActivity.party:
      return "Photo of people celebrating together";
    case PeopleActivity.hiking:
      return "Photo of people hiking or walking together in nature";
    case PeopleActivity.feast:
      return "Photo of people having a big feast together";
    case PeopleActivity.selfies:
      return "Happy and nostalgic selfie with people, clearly taken from the front camera of a phone";
    case PeopleActivity.posing:
      return "Photo of people posing together in a funny manner for the camera";
    case PeopleActivity.background:
      return "Photo of people with an absolutely stunning or interesting background";
    case PeopleActivity.sports:
      return "Photo of people joyfully playing sports together";
    case PeopleActivity.roadtrip:
      return "Photo of people on a road trip together";
  }
}

String activityTitle(
  AppLocalizations locals,
  PeopleActivity activity,
  String personName,
) {
  switch (activity) {
    case PeopleActivity.admiring:
      return locals.admiringThem(name: personName);
    case PeopleActivity.embracing:
      return locals.embracingThem(name: personName);
    case PeopleActivity.party:
      return locals.partyWithThem(name: personName);
    case PeopleActivity.hiking:
      return locals.hikingWithThem(name: personName);
    case PeopleActivity.feast:
      return locals.feastingWithThem(name: personName);
    case PeopleActivity.selfies:
      return locals.selfiesWithThem(name: personName);
    case PeopleActivity.posing:
      return locals.posingWithThem(name: personName);
    case PeopleActivity.background:
      return locals.backgroundWithThem(name: personName);
    case PeopleActivity.sports:
      return locals.sportsWithThem(name: personName);
    case PeopleActivity.roadtrip:
      return locals.roadtripWithThem(name: personName);
  }
}

class PeopleMemory extends SmartMemory {
  final String personID;
  final PeopleMemoryType peopleMemoryType;
  final PeopleActivity? activity;
  final String? personName;
  final bool isUnnamedCluster;
  final bool? isBirthday;
  final int? newAge;

  PeopleMemory(
    List<Memory> memories,
    int firstDateToShow,
    int lastDateToShow,
    this.peopleMemoryType,
    this.personID,
    this.personName, {
    String? title,
    String? id,
    super.firstCreationTime,
    super.lastCreationTime,
    this.activity,
    this.isUnnamedCluster = false,
    this.isBirthday,
    this.newAge,
  }) : super(
         memories,
         MemoryType.people,
         title ?? '',
         firstDateToShow,
         lastDateToShow,
         id: id,
       );

  PeopleMemory copyWith({
    int? firstDateToShow,
    int? lastDateToShow,
    bool? isUnnamedCluster,
    bool? isBirthday,
    int? newAge,
  }) {
    return PeopleMemory(
      memories,
      firstDateToShow ?? this.firstDateToShow,
      lastDateToShow ?? this.lastDateToShow,
      peopleMemoryType,
      personID,
      personName,
      firstCreationTime: firstCreationTime,
      lastCreationTime: lastCreationTime,
      activity: activity,
      isUnnamedCluster: isUnnamedCluster ?? this.isUnnamedCluster,
      isBirthday: isBirthday ?? this.isBirthday,
      newAge: newAge ?? this.newAge,
    );
  }

  @override
  String createTitle(AppLocalizations locals, String languageCode) {
    if (isUnnamedCluster) {
      switch (peopleMemoryType) {
        case PeopleMemoryType.youAndThem:
          return locals.unnamedPeopleYouAndThem;
        case PeopleMemoryType.doingSomethingTogether:
          return locals.unnamedPeopleDoingSomethingTogether;
        case PeopleMemoryType.spotlight:
          return locals.unnamedPeopleSpotlight;
        case PeopleMemoryType.lastTimeYouSawThem:
          return locals.unnamedPeopleThrowbackTogether;
      }
    }
    switch (peopleMemoryType) {
      case PeopleMemoryType.youAndThem:
        assert(personName != null);
        return locals.youAndThem(name: personName!);
      case PeopleMemoryType.doingSomethingTogether:
        assert(activity != null);
        assert(personName != null);
        return activityTitle(locals, activity!, personName!);
      case PeopleMemoryType.spotlight:
        if (personName == null) {
          return locals.spotlightOnYourself;
        } else if (newAge == null) {
          return locals.spotlightOnThem(name: personName!);
        } else {
          if (isBirthday!) {
            return locals.personIsAge(name: personName!, age: newAge!);
          } else {
            return locals.personTurningAge(name: personName!, age: newAge!);
          }
        }
      case PeopleMemoryType.lastTimeYouSawThem:
        return locals.throwbackWithThem(name: personName!);
    }
  }
}

typedef PeopleSelectionBuilder =
    Future<List<Memory>> Function(List<Memory> memories);

class PeopleMemoryCandidate {
  PeopleMemoryCandidate({
    required this.personID,
    required this.personName,
    required this.type,
    required this.rawMemories,
    required this.firstDateToShow,
    required this.lastDateToShow,
    this.activity,
    this.isUnnamedCluster = false,
    this.lastCreationTime,
    this.selectionBuilder,
    this.requiresSelection = true,
  }) : assert(!requiresSelection || selectionBuilder != null);

  final String personID;
  final String? personName;
  final PeopleMemoryType type;
  final PeopleActivity? activity;
  final bool isUnnamedCluster;
  final List<Memory> rawMemories;
  final int firstDateToShow;
  final int lastDateToShow;
  final int? lastCreationTime;
  final bool requiresSelection;
  final PeopleSelectionBuilder? selectionBuilder;

  PeopleMemory? _resolvedMemory;
  Future<PeopleMemory?>? _pendingBuild;

  Future<PeopleMemory?> realize() {
    if (_resolvedMemory != null) return Future.value(_resolvedMemory);
    _pendingBuild ??= _build();
    return _pendingBuild!;
  }

  Future<PeopleMemory?> _build() async {
    List<Memory> memories = rawMemories;
    if (requiresSelection) {
      final builder = selectionBuilder;
      if (builder == null) return null;
      final selection = await builder(rawMemories);
      if (selection.isEmpty) return null;
      memories = selection;
    }
    _resolvedMemory = PeopleMemory(
      memories,
      firstDateToShow,
      lastDateToShow,
      type,
      personID,
      personName,
      lastCreationTime: lastCreationTime,
      activity: activity,
      isUnnamedCluster: isUnnamedCluster,
    );
    return _resolvedMemory;
  }
}
