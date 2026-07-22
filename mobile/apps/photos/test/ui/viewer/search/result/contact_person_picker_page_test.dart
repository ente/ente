import "package:flutter_test/flutter_test.dart";
import "package:photos/models/ml/face/person.dart";
import "package:photos/models/search/search_constants.dart";
import "package:photos/ui/viewer/search/result/contact_person_picker_page.dart";

void main() {
  test("includes unassigned face clusters alongside existing people", () {
    final person = PersonEntity("person-1", PersonData(name: "Alex"));

    final candidates = buildContactPersonPickerCandidates(
      faceResultParams: const [
        {kPersonParamID: "person-1"},
        {kClusterParamId: "cluster-1"},
      ],
      persons: [person],
    );

    expect(candidates, hasLength(2));
    expect(
      (candidates.first as ContactPersonPickerPersonCandidate).person,
      same(person),
    );
    expect(
      (candidates.last as ContactPersonPickerClusterCandidate).clusterID,
      "cluster-1",
    );
  });
}
