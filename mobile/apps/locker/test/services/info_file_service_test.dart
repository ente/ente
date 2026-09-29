import "package:flutter_test/flutter_test.dart";
import "package:locker/models/file_type.dart";
import "package:locker/models/info/info_item.dart";
import "package:locker/services/files/sync/models/file.dart";
import "package:locker/services/files/sync/models/file_magic.dart";
import "package:locker/services/info_file_service.dart";

void main() {
  group("InfoFileService.extractInfoFromFile", () {
    test("reads partial records with omitted optional fields", () {
      final secretFile = EnteFile()
        ..fileType = FileType.info
        ..title = "Netflix"
        ..pubMagicMetadata = PubMagicMetadata(
          info: {
            "type": "accountCredential",
            "data": {"name": "Netflix", "notes": "Ask Sam"},
          },
          noThumb: true,
        );
      final thingFile = EnteFile()
        ..fileType = FileType.info
        ..title = "Passport"
        ..pubMagicMetadata = PubMagicMetadata(
          info: {
            "type": "physicalRecord",
            "data": {"name": "Passport"},
          },
          noThumb: true,
        );

      final secretItem = InfoFileService.instance.extractInfoFromFile(
        secretFile,
      )!;
      final secret = secretItem.data as AccountCredentialData;
      final thing =
          InfoFileService.instance.extractInfoFromFile(thingFile)!.data
              as PhysicalRecordData;

      expect(secret.username, isEmpty);
      expect(secret.password, isEmpty);
      expect(secret.notes, "Ask Sam");
      expect(thing.location, isEmpty);
      expect(InfoFileService.instance.getInfoFileTitle(secretItem), "Netflix");
    });

    test("parses hyphenated account credential types", () {
      final file = EnteFile()
        ..fileType = FileType.info
        ..title = "GitHub"
        ..pubMagicMetadata = PubMagicMetadata(
          info: {
            "type": "account-credential",
            "data": {
              "name": "GitHub",
              "username": "octocat",
              "password": "secret",
            },
          },
          noThumb: true,
        );

      final item = InfoFileService.instance.extractInfoFromFile(file);

      expect(item, isNotNull);
      expect(item!.type, InfoType.accountCredential);

      final data = item.data as AccountCredentialData;
      expect(data.name, "GitHub");
      expect(data.username, "octocat");
      expect(data.password, "secret");
    });

    test("parses hyphenated physical record types", () {
      final file = EnteFile()
        ..fileType = FileType.info
        ..title = "Passport"
        ..pubMagicMetadata = PubMagicMetadata(
          info: {
            "type": "physical-record",
            "data": {
              "name": "Passport",
              "location": "Home safe",
              "notes": "Top shelf",
            },
          },
          noThumb: true,
        );

      final item = InfoFileService.instance.extractInfoFromFile(file);

      expect(item, isNotNull);
      expect(item!.type, InfoType.physicalRecord);

      final data = item.data as PhysicalRecordData;
      expect(data.name, "Passport");
      expect(data.location, "Home safe");
      expect(data.notes, "Top shelf");
    });
  });
}
