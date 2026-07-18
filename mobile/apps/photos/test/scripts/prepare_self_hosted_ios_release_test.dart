import "dart:convert";
import "dart:io";

import "package:path/path.dart" as p;
import "package:test/test.dart";

import "../../scripts/prepare_self_hosted_ios_release.dart";

const _team = "ABCDEFGHIJ";
const _endpoint = "https://museum.example";
const _commit = "0123456789abcdef0123456789abcdef01234567";

void main() {
  test("parses the required iOS preparation inputs", () {
    final options = IOSPreparationOptions.parse(const [
      "--output-dir",
      "/tmp/ios-releases",
    ], environment: _environment());

    expect(options.outputDirectory, "/tmp/ios-releases");
    expect(options.endpoint, "https://Museum.Example/");
    expect(options.distributionTeam, _team);
    expect(options.expectedDeviceCount, 1);
    expect(options.marketingVersion, "1.3.59");
    expect(options.buildNumber, 2159);
  });

  test("rejects incomplete or unsafe preparation inputs", () {
    expect(
      () => IOSPreparationOptions.parse(const [
        "--output-dir",
        "relative",
      ], environment: _environment()),
      throwsA(
        isA<IOSReleasePreparationException>().having(
          (error) => error.exitCode,
          "exitCode",
          64,
        ),
      ),
    );
    expect(
      () => IOSPreparationOptions.parse(
        const ["--output-dir", "/tmp/ios-releases"],
        environment: <String, String>{..._environment()}
          ..remove("ENTE_IOS_ADHOC_PROFILE"),
      ),
      throwsA(isA<IOSReleasePreparationException>()),
    );
  });

  test("canonicalizes HTTPS origins and rejects unsafe endpoints", () {
    expect(
      canonicalizeConfigurableEndpoint("https://Museum.Example/"),
      _endpoint,
    );
    expect(
      () => canonicalizeConfigurableEndpoint("http://museum.example"),
      throwsA(isA<IOSReleasePreparationException>()),
    );
  });

  test("normalizes supported GitHub source remotes", () {
    expect(
      normalizeGitHubSourceBaseUrl("https://github.com/vanton1/ente.git"),
      "https://github.com/vanton1/ente",
    );
    expect(
      normalizeGitHubSourceBaseUrl("git@github.com:vanton1/ente.git"),
      "https://github.com/vanton1/ente",
    );
    expect(
      () => normalizeGitHubSourceBaseUrl("/tmp/local-repository"),
      throwsA(isA<IOSReleasePreparationException>()),
    );
  });

  test("parses the committed marketing version", () {
    expect(
      parsePubspecMarketingVersion("name: photos\nversion: 1.3.59+2158\n"),
      "1.3.59",
    );
    expect(
      () => parsePubspecMarketingVersion("name: photos\n"),
      throwsA(isA<IOSReleasePreparationException>()),
    );
  });

  test("strips Firebase and Google credentials from the build environment", () {
    final result = sanitizedIOSPreparationEnvironment(<String, String>{
      "PATH": "/usr/bin:/bin",
      "HOME": "/tmp/home",
      "FIREBASE_TOKEN": "secret",
      "FIREBASE_CLI": "/tmp/firebase",
      "ENTE_FIREBASE_IOS_APP_ID": "private-binding",
      "GOOGLE_APPLICATION_CREDENTIALS": "/tmp/key.json",
      "GCLOUD_PROJECT": "project",
      "ENTE_IOS_DISTRIBUTION_TEAM": _team,
    });

    expect(result["PATH"], "/usr/bin:/bin");
    expect(result["ENTE_IOS_DISTRIBUTION_TEAM"], _team);
    expect(result, isNot(contains("FIREBASE_TOKEN")));
    expect(result, isNot(contains("FIREBASE_CLI")));
    expect(result, isNot(contains("ENTE_FIREBASE_IOS_APP_ID")));
    expect(result, isNot(contains("GOOGLE_APPLICATION_CREDENTIALS")));
    expect(result, isNot(contains("GCLOUD_PROJECT")));
  });

  test("limits Rust codegen to toolchain and cache paths", () {
    final result = sanitizedIOSCodegenEnvironment(const <String, String>{
      "PATH": "/usr/bin:/bin",
      "HOME": "/tmp/home",
      "CARGO_HOME": "/tmp/cargo",
      "RUSTUP_HOME": "/tmp/rustup",
      "DART_BIN": "/tmp/flutter/bin/dart",
      "FLUTTER_BIN": "/tmp/flutter/bin/flutter",
      "FIREBASE_CLI": "/tmp/firebase",
      "FIREBASE_TOKEN": "secret",
      "ENTE_FIREBASE_IOS_APP_ID": "private-binding",
      "ENTE_IOS_ADHOC_PROFILE": "/tmp/private.mobileprovision",
      "ENTE_SELF_HOSTED_ENDPOINT": _endpoint,
      "GOOGLE_APPLICATION_CREDENTIALS": "/tmp/key.json",
      "GCLOUD_PROJECT": "project",
      "SSH_AUTH_SOCK": "/tmp/agent.sock",
      "DEVELOPMENT_TEAM": _team,
      "CODE_SIGN_IDENTITY": "private identity",
      "PROVISIONING_PROFILE_SPECIFIER": "private profile",
      "APPLE_ID": "private@example.invalid",
      "APPLE_APP_SPECIFIC_PASSWORD": "secret",
      "FASTLANE_SESSION": "secret",
      "MATCH_PASSWORD": "secret",
      "APP_STORE_CONNECT_API_KEY": "secret",
      "ASC_KEY": "secret",
      "AWS_SECRET_ACCESS_KEY": "secret",
      "AZURE_CREDENTIALS": "secret",
      "CUSTOM_PASSWORD": "secret",
      "CUSTOM_PRIVATE_KEY": "secret",
      "CUSTOM_SECRET": "secret",
      "SENTRY_AUTH_TOKEN": "secret",
      "CUSTOM_CREDENTIALS": "secret",
    });

    expect(result, <String, String>{
      "PATH": "/usr/bin:/bin",
      "HOME": "/tmp/home",
      "CARGO_HOME": "/tmp/cargo",
      "RUSTUP_HOME": "/tmp/rustup",
      "DART_BIN": "/tmp/flutter/bin/dart",
      "FLUTTER_BIN": "/tmp/flutter/bin/flutter",
    });
  });

  test(
    "generates every required Rust binding with the official command",
    () async {
      final root = Directory.systemTemp.createTempSync(
        "ente-ios-binding-generation-test-",
      );
      try {
        final rustDirectory = Directory(p.join(root.path, "rust"))
          ..createSync();
        File(
          p.join(rustDirectory.path, "Cargo.toml"),
        ).writeAsStringSync("[workspace]\n");
        final binDirectory = Directory(p.join(root.path, "bin"))..createSync();
        final cargo = File(p.join(binDirectory.path, "cargo"))
          ..writeAsStringSync(_fakeCargoScript(writesBindings: true));
        await Process.run("chmod", ["+x", cargo.path]);

        await generateIOSReleaseBindings(
          checkoutDirectory: root.path,
          environment: <String, String>{
            "PATH": binDirectory.path,
            "HOME": p.join(root.path, "home"),
          },
        );

        expect(
          File(p.join(root.path, "cargo-invocation.txt")).readAsStringSync(),
          "codegen frb\n",
        );
        for (final relativePath in requiredGeneratedIOSBindingPaths) {
          expect(
            File(p.join(root.path, relativePath)).lengthSync(),
            greaterThan(0),
          );
        }
      } finally {
        root.deleteSync(recursive: true);
      }
    },
  );

  test("rejects incomplete Rust binding generation", () async {
    final root = Directory.systemTemp.createTempSync(
      "ente-ios-binding-generation-missing-test-",
    );
    try {
      final rustDirectory = Directory(p.join(root.path, "rust"))..createSync();
      File(
        p.join(rustDirectory.path, "Cargo.toml"),
      ).writeAsStringSync("[workspace]\n");
      final binDirectory = Directory(p.join(root.path, "bin"))..createSync();
      final cargo = File(p.join(binDirectory.path, "cargo"))
        ..writeAsStringSync(_fakeCargoScript(writesBindings: false));
      await Process.run("chmod", ["+x", cargo.path]);

      await expectLater(
        generateIOSReleaseBindings(
          checkoutDirectory: root.path,
          environment: <String, String>{
            "PATH": binDirectory.path,
            "HOME": p.join(root.path, "home"),
          },
        ),
        throwsA(
          isA<IOSReleasePreparationException>().having(
            (error) => error.exitCode,
            "exitCode",
            65,
          ),
        ),
      );
    } finally {
      root.deleteSync(recursive: true);
    }
  });

  test("accepts safe IPA entries and rejects traversal", () {
    expect(
      () => validateSafeZipEntries(const <String>[
        "Payload/SelfHostedRunner.app/Info.plist",
        "Payload/SelfHostedRunner.app/SelfHostedRunner",
      ]),
      returnsNormally,
    );
    expect(
      () => validateSafeZipEntries(const <String>["Payload/../private/file"]),
      throwsA(isA<IOSReleasePreparationException>()),
    );
  });

  test("parses and validates the core-only signed entitlements", () {
    const output = """
[Dict]
  [Key] application-identifier
  [Value]
    [String] ABCDEFGHIJ.me.vanton.ente.photos.selfhosted
  [Key] com.apple.developer.team-identifier
  [Value]
    [String] ABCDEFGHIJ
  [Key] get-task-allow
  [Value]
    [Bool] false
""";

    final entitlements = parseAbstractCodesignEntitlements(output);
    expect(
      () => validateSignedEntitlements(entitlements, expectedTeam: _team),
      returnsNormally,
    );
    expect(entitlements["get-task-allow"], isFalse);

    expect(
      () => validateSignedEntitlements(<String, Object>{
        ...entitlements,
        "aps-environment": "production",
      }, expectedTeam: _team),
      throwsA(isA<IOSReleasePreparationException>()),
    );
    expect(
      () => validateSignedEntitlements(<String, Object>{
        ...entitlements,
        "get-task-allow": true,
      }, expectedTeam: _team),
      throwsA(isA<IOSReleasePreparationException>()),
    );
  });

  test("distinguishes local trust rejection from signature corruption", () {
    expect(validateCodesignVerification(ProcessResult(1, 0, "", "")), isTrue);
    expect(
      validateCodesignVerification(
        ProcessResult(
          1,
          1,
          "",
          "/tmp/App.app: CSSMERR_TP_NOT_TRUSTED\nIn architecture: arm64",
        ),
      ),
      isFalse,
    );
    expect(
      () => validateCodesignVerification(
        ProcessResult(1, 1, "", "/tmp/App.app: code object is not signed"),
      ),
      throwsA(isA<IOSReleasePreparationException>()),
    );
  });

  test("parses the pinned certificate fingerprint and UTC validity", () {
    final summary = parseOpenSSLCertificateSummary("""
sha256 Fingerprint=8F:CA:F5:F7:61:AC:BC:BE:EA:E4:71:0F:B7:53:70:64:60:71:D8:A9:05:AC:2A:70:FF:EB:46:67:6C:4A:1E:0C
notBefore=Jul 17 11:30:00 2026 GMT
notAfter=Jul 17 11:30:00 2027 GMT
""");

    expect(summary.sha256, expectedDistributionCertificateSha256);
    expect(summary.notBefore, DateTime.utc(2026, 7, 17, 11, 30));
    expect(summary.notAfter, DateTime.utc(2027, 7, 17, 11, 30));
  });

  test("writes a read-only IPA/manifest pair and refuses overwrite", () async {
    final temporaryDirectory = Directory.systemTemp.createTempSync(
      "ente-ios-finalization-test-",
    );
    try {
      final sourceIpa = File(p.join(temporaryDirectory.path, "source.ipa"))
        ..writeAsBytesSync(utf8.encode("audited ipa bytes"));
      final outputDirectory = Directory(
        p.join(temporaryDirectory.path, "prepared"),
      )..createSync();
      final sha256 = await sha256File(sourceIpa.path);
      final audit = await _auditForFixture(sourceIpa.path, sha256: sha256);

      final result = await finalizePreparedIOSRelease(
        buildIpaPath: sourceIpa.path,
        audit: audit,
        outputDirectory: outputDirectory.path,
        commit: _commit,
        origin: "https://github.com/vanton1/ente.git",
        sourceCommitUrl: "https://github.com/vanton1/ente/commit/$_commit",
        preparationSourceSha256:
            "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        xcodeVersion: const XcodeVersion(
          version: "26.6",
          buildVersion: "17G86",
        ),
      );

      final manifest =
          jsonDecode(File(result.manifestPath).readAsStringSync())
              as Map<String, dynamic>;
      expect(
        File(result.ipaPath).readAsBytesSync(),
        sourceIpa.readAsBytesSync(),
      );
      expect(manifest["schemaVersion"], releaseManifestSchemaVersion);
      expect(manifest["artifact"]["sha256"], sha256);
      expect(manifest["source"]["isolatedCheckout"], isTrue);
      expect(manifest["ios"]["authorizedDeviceIdentifiers"], isNull);
      expect(manifest["ios"]["profile"]["authorizedDeviceCount"], 1);
      expect(File(result.ipaPath).statSync().mode & 0x1ff, 0x124);
      expect(File(result.manifestPath).statSync().mode & 0x1ff, 0x124);

      await expectLater(
        finalizePreparedIOSRelease(
          buildIpaPath: sourceIpa.path,
          audit: audit,
          outputDirectory: outputDirectory.path,
          commit: _commit,
          origin: "https://github.com/vanton1/ente.git",
          sourceCommitUrl: "https://github.com/vanton1/ente/commit/$_commit",
          preparationSourceSha256:
              "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
          xcodeVersion: const XcodeVersion(
            version: "26.6",
            buildVersion: "17G86",
          ),
        ),
        throwsA(
          isA<IOSReleasePreparationException>().having(
            (error) => error.exitCode,
            "exitCode",
            73,
          ),
        ),
      );
    } finally {
      temporaryDirectory.deleteSync(recursive: true);
    }
  });

  test(
    "builds from a clean pushed worktree despite unrelated primary dirt",
    () async {
      final fixture = await _IsolationFixture.create();
      try {
        var generatedBindings = false;
        final result = await prepareSelfHostedIOSRelease(
          fixture.options,
          appDirectoryOverride: fixture.appDirectory,
          bindingGenerator:
              ({required checkoutDirectory, required environment}) async {
                generatedBindings = true;
                expect(checkoutDirectory, isNot(fixture.repositoryRoot));
                expect(
                  p.isWithin(fixture.repositoryRoot, checkoutDirectory),
                  isFalse,
                );
                expect(environment, isNot(contains("FIREBASE_TOKEN")));
                expect(environment, isNot(contains("ENTE_IOS_ADHOC_PROFILE")));
                expect(
                  environment,
                  isNot(contains("ENTE_SELF_HOSTED_ENDPOINT")),
                );
              },
          auditor:
              ({
                required ipaPath,
                required canonicalEndpoint,
                required expectedTeam,
                required expectedDeviceCount,
                required expectedMarketingVersion,
                required expectedBuildNumber,
                required tools,
                processEnvironment,
              }) async {
                final contents = File(ipaPath).readAsStringSync().trim();
                expect(contents, fixture.commit);
                expect(canonicalEndpoint, _endpoint);
                expect(expectedTeam, _team);
                expect(expectedDeviceCount, 1);
                expect(expectedMarketingVersion, "1.3.59");
                expect(expectedBuildNumber, 2159);
                final sha256 = await sha256File(ipaPath);
                return _auditForFixture(ipaPath, sha256: sha256);
              },
        );

        final manifest =
            jsonDecode(File(result.manifestPath).readAsStringSync())
                as Map<String, dynamic>;
        expect(manifest["source"]["commit"], fixture.commit);
        expect(manifest["source"]["isolatedCheckout"], isTrue);
        expect(manifest["source"]["checkoutCleanBeforeBuild"], isTrue);
        expect(manifest["source"]["checkoutCleanAfterAudit"], isTrue);
        expect(generatedBindings, isTrue);
        expect(manifest["build"]["rustBindingsGeneratedFromCheckout"], isTrue);
        expect(
          Directory(fixture.options.outputDirectory).statSync().mode & 0x1ff,
          0x1c0,
        );
        expect(
          File(
            p.join(fixture.repositoryRoot, "unrelated-note.txt"),
          ).existsSync(),
          isTrue,
        );
        final worktrees = await _git(fixture.repositoryRoot, const [
          "worktree",
          "list",
          "--porcelain",
        ]);
        expect(
          RegExp(r"^worktree ", multiLine: true).allMatches(worktrees).length,
          1,
        );
      } finally {
        fixture.dispose();
      }
    },
  );

  final integrationIpa = Platform.environment["ENTE_TEST_RELEASE_IPA"];
  if (integrationIpa != null) {
    test("audits the real owner Ad Hoc IPA", () async {
      final environment = Platform.environment;
      final audit = await auditIOSReleaseIpa(
        ipaPath: integrationIpa,
        canonicalEndpoint: environment["ENTE_SELF_HOSTED_ENDPOINT"]!,
        expectedTeam: environment["ENTE_IOS_DISTRIBUTION_TEAM"]!,
        expectedDeviceCount: int.parse(
          environment["ENTE_IOS_EXPECTED_DEVICE_COUNT"]!,
        ),
        expectedMarketingVersion: environment["ENTE_IOS_MARKETING_VERSION"]!,
        expectedBuildNumber: int.parse(environment["ENTE_IOS_BUILD_NUMBER"]!),
        tools: IOSReleaseToolPaths.fromEnvironment(environment),
        processEnvironment: environment,
      );

      expect(audit.bundleIdentifier, expectedBundleIdentifier);
      expect(audit.architectures, expectedArchitectures);
      expect(audit.machOCount, greaterThan(0));
      expect(audit.debuggable, isFalse);
      expect(audit.extensionCount, 0);
      expect(
        audit.signingCertificateSha256,
        expectedDistributionCertificateSha256,
      );
      expect(audit.authorizedDeviceCount, 1);
    });
  }
}

String _fakeCargoScript({required bool writesBindings}) {
  final writes = writesBindings
      ? requiredGeneratedIOSBindingPaths.map((relativePath) {
          return r'''
path="$repo/@@PATH@@"
/bin/mkdir -p "${path%/*}"
/usr/bin/printf 'generated\n' >"$path"
'''
              .replaceAll("@@PATH@@", relativePath);
        }).join()
      : "";
  return r'''
#!/bin/bash
set -euo pipefail
if [[ "$#" -ne 2 || "$1" != "codegen" || "$2" != "frb" ]]; then
  exit 64
fi
repo="$(cd .. && /bin/pwd)"
/usr/bin/printf '%s %s\n' "$1" "$2" >"$repo/cargo-invocation.txt"
@@WRITES@@
'''
      .replaceAll("@@WRITES@@", writes);
}

Map<String, String> _environment() => <String, String>{
  ...Platform.environment,
  "ENTE_SELF_HOSTED_ENDPOINT": "https://Museum.Example/",
  "ENTE_IOS_DISTRIBUTION_TEAM": _team,
  "ENTE_IOS_ADHOC_PROFILE": "/tmp/profile.mobileprovision",
  "ENTE_IOS_EXPECTED_DEVICE_COUNT": "1",
  "ENTE_IOS_MARKETING_VERSION": "1.3.59",
  "ENTE_IOS_BUILD_NUMBER": "2159",
};

Future<IOSReleaseAudit> _auditForFixture(
  String ipaPath, {
  required String sha256,
}) async => IOSReleaseAudit(
  bundleIdentifier: expectedBundleIdentifier,
  marketingVersion: "1.3.59",
  buildNumber: 2159,
  compiledDefaultEndpoint: _endpoint,
  architectures: expectedArchitectures,
  machOCount: 1,
  debuggable: false,
  extensionCount: 0,
  signedEntitlementKeys: expectedSignedEntitlementKeys,
  applicationIdentifier: "$_team.$expectedBundleIdentifier",
  teamIdentifier: _team,
  profileName: "Owner Ad Hoc",
  profileUuid: "01234567-89AB-CDEF-0123-456789ABCDEF",
  profileExpiration: DateTime.utc(2027, 7, 17),
  authorizedDeviceCount: 1,
  signingCertificateSha256: expectedDistributionCertificateSha256,
  certificateNotBefore: DateTime.utc(2026, 7, 17),
  certificateNotAfter: DateTime.utc(2027, 7, 17),
  deepSignatureStructureValid: true,
  localTrustChainAccepted: false,
  sha256: sha256,
  sizeBytes: File(ipaPath).lengthSync(),
);

class _IsolationFixture {
  _IsolationFixture({
    required this.root,
    required this.repositoryRoot,
    required this.appDirectory,
    required this.commit,
    required this.options,
  });

  static Future<_IsolationFixture> create() async {
    final root = Directory.systemTemp.createTempSync(
      "ente-ios-isolation-test-",
    );
    final repositoryRoot = p.join(root.path, "repository");
    final appDirectory = p.join(repositoryRoot, "mobile", "apps", "photos");
    final scriptsDirectory = Directory(p.join(appDirectory, "scripts"))
      ..createSync(recursive: true);
    File(
      p.join(appDirectory, "pubspec.yaml"),
    ).writeAsStringSync("name: photos\nversion: 1.3.59+2158\n");
    File(
      p.join(scriptsDirectory.path, "prepare_self_hosted_ios_release.dart"),
    ).writeAsStringSync("// fixture preparation source\n");
    File(
      p.join(scriptsDirectory.path, "prepare_self_hosted_ios_release.sh"),
    ).writeAsStringSync("#!/bin/bash\nexit 0\n");
    final builder =
        File(p.join(scriptsDirectory.path, "build_self_hosted_ios.sh"))
          ..writeAsStringSync("""
#!/bin/bash
set -euo pipefail
/bin/mkdir -p "\$ENTE_IOS_ARCHIVE_PATH" "\$ENTE_IOS_EXPORT_PATH"
/usr/bin/git rev-parse HEAD >"\$ENTE_IOS_EXPORT_PATH/Fixture.ipa"
""");
    await Process.run("chmod", ["+x", builder.path]);

    final fakeXcodebuild = File(p.join(root.path, "xcodebuild"))
      ..writeAsStringSync("""
#!/bin/bash
printf 'Xcode 26.6\nBuild version 17G86\n'
""");
    await Process.run("chmod", ["+x", fakeXcodebuild.path]);
    final profile = File(p.join(root.path, "profile.mobileprovision"))
      ..writeAsStringSync("fixture profile\n");

    Directory(repositoryRoot).createSync(recursive: true);
    await _git(repositoryRoot, const ["init"]);
    await _git(repositoryRoot, const ["config", "user.name", "Fixture"]);
    await _git(repositoryRoot, const [
      "config",
      "user.email",
      "fixture@example.invalid",
    ]);
    await _git(repositoryRoot, const ["add", "."]);
    await _git(repositoryRoot, const ["commit", "-m", "fixture"]);
    final commit = (await _git(repositoryRoot, const [
      "rev-parse",
      "HEAD",
    ])).trim();
    await _git(repositoryRoot, const [
      "remote",
      "add",
      "origin",
      "https://github.com/vanton1/ente.git",
    ]);
    await _git(repositoryRoot, [
      "update-ref",
      "refs/remotes/origin/main",
      commit,
    ]);
    File(p.join(repositoryRoot, "unrelated-note.txt")).writeAsStringSync(
      "primary checkout dirt that must not enter the release\n",
    );

    final outputDirectory = Directory(p.join(root.path, "prepared"))
      ..createSync();
    final environment = <String, String>{
      ...Platform.environment,
      "ENTE_SELF_HOSTED_ENDPOINT": _endpoint,
      "ENTE_IOS_DISTRIBUTION_TEAM": _team,
      "ENTE_IOS_ADHOC_PROFILE": profile.path,
      "ENTE_IOS_EXPECTED_DEVICE_COUNT": "1",
      "ENTE_IOS_MARKETING_VERSION": "1.3.59",
      "ENTE_IOS_BUILD_NUMBER": "2159",
      "XCODEBUILD_BIN": fakeXcodebuild.path,
    };
    return _IsolationFixture(
      root: root,
      repositoryRoot: repositoryRoot,
      appDirectory: appDirectory,
      commit: commit,
      options: IOSPreparationOptions.parse([
        "--output-dir",
        outputDirectory.path,
      ], environment: environment),
    );
  }

  final Directory root;
  final String repositoryRoot;
  final String appDirectory;
  final String commit;
  final IOSPreparationOptions options;

  void dispose() {
    if (root.existsSync()) {
      root.deleteSync(recursive: true);
    }
  }
}

Future<String> _git(String repository, List<String> arguments) async {
  final result = await Process.run(
    "git",
    arguments,
    workingDirectory: repository,
  );
  if (result.exitCode != 0) {
    throw StateError("git ${arguments.join(" ")} failed: ${result.stderr}");
  }
  return result.stdout as String;
}
