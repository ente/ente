import "package:flutter_test/flutter_test.dart";
import "package:photos/models/api/collection/user.dart";

void main() {
  test("older participant data remains accepted", () {
    for (final map in [
      {"id": 1, "email": "friend@example.com"},
      {"id": 1, "email": "friend@example.com", "acceptanceStatus": null},
    ]) {
      final user = User.fromMap(map);
      expect(user.acceptanceStatus, "accepted");
      expect(user.isPending, isFalse);
    }
  });

  test("pending status survives persistence and role changes", () {
    final user = User.fromMap({
      "id": 1,
      "email": "friend@example.com",
      "role": "VIEWER",
      "acceptanceStatus": "pending",
    });
    user.role = "ADMIN";

    final restored = User.fromJson(user.toJson());
    expect(restored.isPending, isTrue);
    expect(restored.role, "ADMIN");
    expect(restored.toMap()["acceptanceStatus"], "pending");
  });
}
