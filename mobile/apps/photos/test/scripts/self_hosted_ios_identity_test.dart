import "dart:io";

import "package:flutter_test/flutter_test.dart";

const expectedBundleIdentifier = "me.vanton.ente.photos.selfhosted";
const expectedAppGroupPlaceholder = "group.me.vanton.ente.photos.selfhosted";
const legacyBundleIdentifier = "com.vanton1.ente.photos.selfhosted";

void main() {
  test("pins the replacement identity in the self-hosted Xcode config", () {
    final config = File("ios/Flutter/SelfHosted.xcconfig").readAsStringSync();
    final settings = _parseXcconfig(config);

    expect(settings["PRODUCT_BUNDLE_IDENTIFIER"], expectedBundleIdentifier);
    expect(settings["CUSTOM_GROUP_ID"], expectedAppGroupPlaceholder);
    expect(config, isNot(contains(legacyBundleIdentifier)));
  });

  test("keeps the self-hosted target core-only", () {
    final entitlements = File(
      "ios/Runner/SelfHostedRunner.entitlements",
    ).readAsStringSync();
    final project = File(
      "ios/Runner.xcodeproj/project.pbxproj",
    ).readAsStringSync();
    final target = RegExp(
      r'5E1F00000000000000000001 /\* SelfHostedRunner \*/ = \{'
      r'(.*?)productType = "com\.apple\.product-type\.application";\s*\};',
      dotAll: true,
    ).firstMatch(project);

    expect(entitlements, matches(RegExp(r"<dict\s*/>")));
    expect(entitlements, isNot(contains("<key>")));
    expect(target, isNotNull);
    expect(target!.group(1), contains("dependencies = (\n\t\t\t);"));
    expect(target.group(1), isNot(contains("ShareExtension")));
    expect(target.group(1), isNot(contains("Widget")));
  });
}

Map<String, String> _parseXcconfig(String config) {
  final settings = <String, String>{};
  for (final line in config.split("\n")) {
    final match = RegExp(r"^([A-Z0-9_]+)\s*=\s*(.*?)\s*$").firstMatch(line);
    if (match != null) {
      settings[match.group(1)!] = match.group(2)!;
    }
  }
  return settings;
}
