import "dart:io";

import "package:flutter_test/flutter_test.dart";

const _bundleIdentifier = "me.vanton.ente.photos.selfhosted";
const _profileUuid = "11111111-2222-3333-4444-555555555555";
const _teamId = "TESTTEAM01";
const _certificateSha1 = "0123456789ABCDEF0123456789ABCDEF01234567";
const _certificateSha256 =
    "8FCAF5F761ACBCBEEAE4710FB75370646071D8A905AC2A70FFEB46676C4A1E0C";

void main() {
  group("self-hosted iOS Ad Hoc archive wrapper", () {
    late _Fixture fixture;

    setUp(() {
      fixture = _Fixture.create();
    });

    tearDown(() {
      fixture.dispose();
    });

    test(
      "creates one manually signed archive and IPA with pinned inputs",
      () async {
        final result = await fixture.run();

        expect(result.exitCode, 0, reason: result.stderr as String);
        expect(Directory(fixture.archivePath).existsSync(), isTrue);
        expect(
          File("${fixture.exportPath}/SelfHostedRunner.ipa").existsSync(),
          isTrue,
        );

        final installedProfile = File(
          "${fixture.home.path}/Library/Developer/Xcode/UserData/Provisioning Profiles/$_profileUuid.mobileprovision",
        );
        expect(installedProfile.existsSync(), isTrue);
        expect(installedProfile.statSync().mode & 0x1ff, 0x180);

        final toolLog = File(fixture.toolLogPath).readAsStringSync();
        expect(toolLog, contains("flutter\tbuild\tios\t--release"));
        expect(toolLog, contains("--build-name=1.3.59"));
        expect(toolLog, contains("--build-number=2159"));
        expect(toolLog, contains("--flavor\tselfhosted"));
        expect(toolLog, contains("--config-only\t--no-codesign"));
        expect(toolLog, contains("xcodebuild\tarchive"));
        expect(toolLog, contains("CODE_SIGN_STYLE=Manual"));
        expect(toolLog, contains("CODE_SIGN_IDENTITY=$_certificateSha1"));
        expect(
          toolLog,
          contains("PROVISIONING_PROFILE_SPECIFIER=$_profileUuid"),
        );
        expect(toolLog, contains("xcodebuild\t-exportArchive"));
        expect(toolLog, isNot(contains("-allowProvisioningUpdates")));
        expect(
          toolLog,
          isNot(contains("-allowProvisioningDeviceRegistration")),
        );

        expect(
          _plistValue(fixture.exportOptionsCapture, "method"),
          "release-testing",
        );
        expect(
          _plistValue(fixture.exportOptionsCapture, "destination"),
          "export",
        );
        expect(
          _plistValue(fixture.exportOptionsCapture, "signingStyle"),
          "manual",
        );
        expect(_plistValue(fixture.exportOptionsCapture, "teamID"), _teamId);
        expect(
          _plistValue(fixture.exportOptionsCapture, "signingCertificate"),
          _certificateSha1,
        );
        expect(
          _plistValue(
            fixture.exportOptionsCapture,
            "provisioningProfiles:$_bundleIdentifier",
          ),
          _profileUuid,
        );
      },
    );

    test("preflights signing inputs without invoking build tools", () async {
      final result = await fixture.run(arguments: ["--adhoc-preflight"]);

      expect(result.exitCode, 0, reason: result.stderr as String);
      expect(result.stdout, contains("archive preflight passed"));
      expect(Directory(fixture.archivePath).existsSync(), isFalse);
      expect(Directory(fixture.exportPath).existsSync(), isFalse);
      expect(File(fixture.toolLogPath).existsSync(), isFalse);
      expect(File(fixture.exportOptionsCapture).existsSync(), isFalse);
    });

    test("rejects additional command-line build overrides", () async {
      final result = await fixture.run(arguments: ["--adhoc", "--release"]);

      expect(result.exitCode, 64);
      expect(result.stderr, contains("must be the only command-line argument"));
      expect(File(fixture.toolLogPath).existsSync(), isFalse);
    });

    test("rejects arguments appended to endpoint validation", () async {
      final result = await fixture.run(
        arguments: ["--validate-only", "--adhoc"],
      );

      expect(result.exitCode, 64);
      expect(result.stderr, contains("does not accept additional arguments"));
      expect(File(fixture.toolLogPath).existsSync(), isFalse);
    });

    test("rejects archive output inside the Git repository", () async {
      fixture.environment["ENTE_IOS_ARCHIVE_PATH"] =
          "${Directory.current.path}/should-never-exist.xcarchive";

      final result = await fixture.run();

      expect(result.exitCode, 64);
      expect(result.stderr, contains("must be outside the Git repository"));
      expect(File(fixture.toolLogPath).existsSync(), isFalse);
    });

    test("rejects an existing archive instead of overwriting it", () async {
      Directory(fixture.archivePath).createSync();

      final result = await fixture.run();

      expect(result.exitCode, 64);
      expect(result.stderr, contains("archive exports never overwrite output"));
      expect(File(fixture.toolLogPath).existsSync(), isFalse);
    });

    test("rejects a profile for another bundle identifier", () async {
      fixture.replaceProfile(
        "$_teamId.$_bundleIdentifier",
        "$_teamId.example.invalid",
      );

      final result = await fixture.run();

      expect(result.exitCode, 64);
      expect(result.stderr, contains("does not match $_bundleIdentifier"));
      expect(File(fixture.toolLogPath).existsSync(), isFalse);
    });

    test("rejects a profile with an unexpected device count", () async {
      fixture.environment["ENTE_IOS_EXPECTED_DEVICE_COUNT"] = "2";

      final result = await fixture.run();

      expect(result.exitCode, 64);
      expect(result.stderr, contains("device count does not match"));
      expect(File(fixture.toolLogPath).existsSync(), isFalse);
    });

    test("rejects a debuggable provisioning profile", () async {
      fixture.replaceProfile("<false/>", "<true/>");

      final result = await fixture.run();

      expect(result.exitCode, 64);
      expect(result.stderr, contains("profile is debuggable"));
      expect(File(fixture.toolLogPath).existsSync(), isFalse);
    });

    test("rejects a profile whose certificate is not pinned", () async {
      fixture.environment["OPENSSL_SHA256"] = List.filled(64, "0").join();

      final result = await fixture.run();

      expect(result.exitCode, 64);
      expect(result.stderr, contains("pinned distribution certificate"));
      expect(File(fixture.toolLogPath).existsSync(), isFalse);
    });

    test(
      "rejects a certificate without a local private-key identity",
      () async {
        fixture.environment["SECURITY_IDENTITY_SHA1"] = List.filled(
          40,
          "0",
        ).join();

        final result = await fixture.run();

        expect(result.exitCode, 64);
        expect(
          result.stderr,
          contains("private-key identity is not available"),
        );
        expect(File(fixture.toolLogPath).existsSync(), isFalse);
      },
    );
  }, skip: !Platform.isMacOS);
}

String _plistValue(String path, String key) {
  final result = Process.runSync("/usr/libexec/PlistBuddy", [
    "-c",
    "Print :$key",
    path,
  ]);
  expect(result.exitCode, 0, reason: result.stderr as String);
  return (result.stdout as String).trim();
}

class _Fixture {
  _Fixture({
    required this.temporaryDirectory,
    required this.home,
    required this.profilePath,
    required this.archivePath,
    required this.exportPath,
    required this.toolLogPath,
    required this.exportOptionsCapture,
    required this.environment,
  });

  factory _Fixture.create() {
    final temporaryDirectory = Directory.systemTemp.createTempSync(
      "ente-ios-adhoc-test-",
    );
    final home = Directory("${temporaryDirectory.path}/home")..createSync();
    final inputs = Directory("${temporaryDirectory.path}/inputs")..createSync();
    final outputs = Directory("${temporaryDirectory.path}/outputs")
      ..createSync();
    final tools = Directory("${temporaryDirectory.path}/tools")..createSync();
    Directory("${temporaryDirectory.path}/tmp").createSync();

    final profilePath = "${inputs.path}/Owner.mobileprovision";
    File(profilePath).writeAsStringSync(_profileFixture);
    final toolLogPath = "${temporaryDirectory.path}/tools.log";
    final exportOptionsCapture =
        "${temporaryDirectory.path}/captured-export-options.plist";

    final dartStub = _writeExecutable(tools, "dart", """#!/bin/bash
set -euo pipefail
printf 'https://museum.example\\n'
""");
    final flutterStub = _writeExecutable(tools, "flutter", """#!/bin/bash
set -euo pipefail
{
  printf 'flutter'
  for argument in "\$@"; do printf '\\t%s' "\$argument"; done
  printf '\\n'
} >>"\$TOOL_LOG"
""");
    final securityStub = _writeExecutable(tools, "security", """#!/bin/bash
set -euo pipefail
if [[ "\${1:-}" == cms ]]; then
  shift
  input=''
  output=''
  while (( \$# )); do
    case "\$1" in
      -i) input="\$2"; shift 2 ;;
      -o) output="\$2"; shift 2 ;;
      *) shift ;;
    esac
  done
  cp "\$input" "\$output"
  exit 0
fi
if [[ "\${1:-}" == find-identity ]]; then
  printf '  1) %s "Apple Distribution: Test"\\n' "\${SECURITY_IDENTITY_SHA1:-$_certificateSha1}"
  printf '     1 valid identities found\\n'
  exit 0
fi
exit 2
""");
    final opensslStub = _writeExecutable(tools, "openssl", """#!/bin/bash
set -euo pipefail
if [[ "\${1:-}" == base64 ]]; then
  cat
  exit 0
fi
if [[ "\${1:-}" == x509 ]]; then
  for argument in "\$@"; do
    if [[ "\$argument" == -checkend ]]; then exit 0; fi
    if [[ "\$argument" == -sha256 ]]; then
      printf 'sha256 Fingerprint=%s\\n' "\${OPENSSL_SHA256:-$_certificateSha256}"
      exit 0
    fi
    if [[ "\$argument" == -sha1 ]]; then
      printf 'sha1 Fingerprint=%s\\n' "$_certificateSha1"
      exit 0
    fi
  done
fi
exit 2
""");
    final xcodebuildStub = _writeExecutable(tools, "xcodebuild", """#!/bin/bash
set -euo pipefail
{
  printf 'xcodebuild'
  for argument in "\$@"; do printf '\\t%s' "\$argument"; done
  printf '\\n'
} >>"\$TOOL_LOG"
mode=''
archive_path=''
export_path=''
export_options=''
while (( \$# )); do
  case "\$1" in
    archive) mode=archive; shift ;;
    -exportArchive) mode=export; shift ;;
    -archivePath) archive_path="\$2"; shift 2 ;;
    -exportPath) export_path="\$2"; shift 2 ;;
    -exportOptionsPlist) export_options="\$2"; shift 2 ;;
    *) shift ;;
  esac
done
if [[ "\$mode" == archive ]]; then
  mkdir -p "\$archive_path"
  exit 0
fi
if [[ "\$mode" == export ]]; then
  mkdir -p "\$export_path"
  : >"\$export_path/SelfHostedRunner.ipa"
  cp "\$export_options" "\$EXPORT_OPTIONS_CAPTURE"
  exit 0
fi
exit 2
""");

    final environment = <String, String>{
      ...Platform.environment,
      "HOME": home.path,
      "TMPDIR": "${temporaryDirectory.path}/tmp",
      "ENTE_SELF_HOSTED_ENDPOINT": "https://museum.example",
      "ENTE_IOS_DISTRIBUTION_TEAM": _teamId,
      "ENTE_IOS_ADHOC_PROFILE": profilePath,
      "ENTE_IOS_EXPECTED_DEVICE_COUNT": "1",
      "ENTE_IOS_MARKETING_VERSION": "1.3.59",
      "ENTE_IOS_BUILD_NUMBER": "2159",
      "ENTE_IOS_ARCHIVE_PATH": "${outputs.path}/Owner.xcarchive",
      "ENTE_IOS_EXPORT_PATH": "${outputs.path}/export",
      "DART_BIN": dartStub,
      "FLUTTER_BIN": flutterStub,
      "SECURITY_BIN": securityStub,
      "OPENSSL_BIN": opensslStub,
      "XCODEBUILD_BIN": xcodebuildStub,
      "PLUTIL_BIN": "/usr/bin/plutil",
      "PLIST_BUDDY_BIN": "/usr/libexec/PlistBuddy",
      "DATE_BIN": "/bin/date",
      "TOOL_LOG": toolLogPath,
      "EXPORT_OPTIONS_CAPTURE": exportOptionsCapture,
    };

    return _Fixture(
      temporaryDirectory: temporaryDirectory,
      home: home,
      profilePath: profilePath,
      archivePath: environment["ENTE_IOS_ARCHIVE_PATH"]!,
      exportPath: environment["ENTE_IOS_EXPORT_PATH"]!,
      toolLogPath: toolLogPath,
      exportOptionsCapture: exportOptionsCapture,
      environment: environment,
    );
  }

  final Directory temporaryDirectory;
  final Directory home;
  final String profilePath;
  final String archivePath;
  final String exportPath;
  final String toolLogPath;
  final String exportOptionsCapture;
  final Map<String, String> environment;

  Future<ProcessResult> run({List<String> arguments = const ["--adhoc"]}) {
    return Process.run(
      "/bin/bash",
      ["scripts/build_self_hosted_ios.sh", ...arguments],
      workingDirectory: Directory.current.path,
      environment: environment,
    );
  }

  void replaceProfile(String from, String to) {
    final profile = File(profilePath);
    profile.writeAsStringSync(
      profile.readAsStringSync().replaceFirst(from, to),
    );
  }

  void dispose() {
    temporaryDirectory.deleteSync(recursive: true);
  }
}

String _writeExecutable(Directory directory, String name, String contents) {
  final file = File("${directory.path}/$name")..writeAsStringSync(contents);
  final chmod = Process.runSync("/bin/chmod", ["700", file.path]);
  if (chmod.exitCode != 0) {
    throw StateError("Could not make ${file.path} executable: ${chmod.stderr}");
  }
  return file.path;
}

const _profileFixture =
    """<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Name</key>
  <string>Owner Ad Hoc</string>
  <key>UUID</key>
  <string>$_profileUuid</string>
  <key>ExpirationDate</key>
  <date>2099-01-01T00:00:00Z</date>
  <key>TeamName</key>
  <string>Test Team</string>
  <key>TeamIdentifier</key>
  <array><string>$_teamId</string></array>
  <key>Entitlements</key>
  <dict>
    <key>application-identifier</key>
    <string>$_teamId.$_bundleIdentifier</string>
    <key>com.apple.developer.team-identifier</key>
    <string>$_teamId</string>
    <key>get-task-allow</key>
    <false/>
  </dict>
  <key>ProvisionedDevices</key>
  <array><string>TEST-DEVICE</string></array>
  <key>DeveloperCertificates</key>
  <array><data>Y2VydA==</data></array>
</dict>
</plist>
""";
