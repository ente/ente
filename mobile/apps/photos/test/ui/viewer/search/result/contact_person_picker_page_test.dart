import "package:flutter_test/flutter_test.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/ml/face/person.dart";
import "package:photos/models/search/generic_search_result.dart";
import "package:photos/models/search/hierarchical/face_filter.dart";
import "package:photos/models/search/search_constants.dart";
import "package:photos/models/search/search_types.dart";
import "package:photos/ui/viewer/search/result/contact_person_picker_page.dart";

void main() {
  test("orders unassigned face clusters by photo frequency", () {
    final person = PersonEntity("person-1", PersonData(name: "Alex"));

    final candidates = buildContactPersonPickerCandidates(
      faceResults: [
        _faceResult(personID: "person-1", fileCount: 2),
        _faceResult(clusterID: "cluster-small", fileCount: 1),
        _faceResult(clusterID: "cluster-large", fileCount: 5),
      ],
      persons: [person],
    );

    expect(candidates, hasLength(3));
    expect(
      (candidates.first as ContactPersonPickerPersonCandidate).person,
      same(person),
    );
    expect(
      candidates
          .skip(1)
          .cast<ContactPersonPickerClusterCandidate>()
          .map((candidate) => candidate.clusterID),
      ["cluster-large", "cluster-small"],
    );
  });
}

GenericSearchResult _faceResult({
  String? personID,
  String? clusterID,
  required int fileCount,
}) {
  final files = List.generate(fileCount, (_) => EnteFile());
  return GenericSearchResult(
    ResultType.faces,
    "",
    files,
    params: {kPersonParamID: ?personID, kClusterParamId: ?clusterID},
    hierarchicalSearchFilter: FaceFilter(
      personId: personID,
      clusterId: clusterID,
      faceName: null,
      faceFile: files.first,
      occurrence: fileCount,
    ),
  );
}
