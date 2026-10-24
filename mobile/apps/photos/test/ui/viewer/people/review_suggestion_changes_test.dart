import "package:flutter_test/flutter_test.dart";
import "package:photos/events/files_updated_event.dart";
import "package:photos/events/people_changed_event.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/ml/face/person.dart";
import "package:photos/services/machine_learning/face_ml/feedback/cluster_feedback.dart";
import "package:photos/ui/viewer/people/review_suggestion_changes.dart";

void main() {
  const affected = reviewSuggestionsAffectedBy;
  final person = PersonEntity("person", PersonData(name: "Alex"));
  final candidates = [
    ClusterSuggestion(person, "cluster", 0.1, false, [
      EnteFile()
        ..uploadedFileID = 7
        ..generatedID = 10,
    ], []),
  ];
  FilesUpdatedEvent fileEvent(
    EventType type, {
    int id = 7,
    String source = "",
  }) => FilesUpdatedEvent(
    [
      EnteFile()
        ..uploadedFileID = id
        ..generatedID = 20,
    ],
    type: type,
    source: source,
  );

  test(
    "file changes match uploaded IDs and preserve move/decorative filters",
    () {
      for (final type in [
        EventType.hide,
        EventType.deletedFromRemote,
        EventType.deletedFromEverywhere,
      ]) {
        expect(affected(fileEvent(type), candidates), isTrue);
        expect(affected(fileEvent(type, id: 99), candidates), isFalse);
      }
      for (final loading in [false, true]) {
        expect(
          affected(
            fileEvent(EventType.coverChanged),
            candidates,
            suggestionsLoading: loading,
          ),
          isFalse,
        );
        expect(
          affected(
            fileEvent(EventType.deletedFromRemote, source: "moveFrom"),
            candidates,
            suggestionsLoading: loading,
          ),
          isFalse,
        );
      }
    },
  );

  test("group edits match cluster IDs once membership is known", () {
    for (final type in [
      PeopleEventType.removedFilesFromCluster,
      PeopleEventType.removedFaceFromCluster,
    ]) {
      expect(
        affected(PeopleChangedEvent(source: "cluster", type: type), candidates),
        isTrue,
      );
      expect(
        affected(PeopleChangedEvent(source: "other", type: type), candidates),
        isFalse,
      );
    }
  });

  test(
    "unscoped changes refresh background cards; preview edits are coalesced",
    () {
      expect(affected(PeopleChangedEvent(), candidates), isTrue);
      expect(affected(PeopleChangedEvent(), const []), isTrue);
      expect(affected(PeopleChangedEvent(person: person), candidates), isFalse);
      expect(
        affected(PeopleChangedEvent(source: "other"), candidates),
        isFalse,
      );
      expect(
        affected(
          PeopleChangedEvent(type: PeopleEventType.syncDone),
          candidates,
        ),
        isFalse,
      );
      expect(
        affected(
          PeopleChangedEvent(person: person),
          candidates,
          previewOpen: true,
        ),
        isTrue,
      );
    },
  );

  test(
    "pending queries invalidate even with a retained, unrelated snapshot",
    () {
      for (final snapshot in [<ClusterSuggestion>[], candidates]) {
        expect(
          affected(
            fileEvent(EventType.hide, id: 99),
            snapshot,
            suggestionsLoading: true,
          ),
          isTrue,
        );
        expect(
          affected(
            PeopleChangedEvent(
              source: "other",
              type: PeopleEventType.removedFilesFromCluster,
            ),
            snapshot,
            suggestionsLoading: true,
          ),
          isTrue,
        );
      }
    },
  );

  test(
    "review notifications refresh all-people or the affected person only",
    () {
      final event = PeopleChangedEvent(
        type: PeopleEventType.reviewedSuggestion,
        person: person,
      );
      expect(affected(event, const []), isTrue);
      expect(affected(event, const [], personID: "person"), isTrue);
      expect(affected(event, candidates, personID: "other"), isFalse);
    },
  );
}
