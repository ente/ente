import "package:flutter_test/flutter_test.dart";
import "package:photos/models/ml/face/person.dart";

void main() {
  group("PersonData.fromJson", () {
    test("treats a missing name as an ignored unnamed person", () {
      final person = PersonData.fromJson({});

      expect(person.name, isEmpty);
      expect(person.isIgnored, isTrue);
    });

    test("treats a null name as an ignored unnamed person", () {
      final person = PersonData.fromJson({
        "name": null,
        "assigned": [
          {
            "id": "cluster-1",
            "faces": ["face-1"],
          },
        ],
      });

      expect(person.name, isEmpty);
      expect(person.isIgnored, isTrue);
      expect(person.assigned.single.id, "cluster-1");
      expect(person.assigned.single.faces, {"face-1"});
    });

    test("preserves a valid name", () {
      final person = PersonData.fromJson({"name": "Alex"});

      expect(person.name, "Alex");
      expect(person.isIgnored, isFalse);
    });

    test("rejects a non-string name", () {
      expect(() => PersonData.fromJson({"name": 7}), throwsA(isA<TypeError>()));
    });
  });
}
