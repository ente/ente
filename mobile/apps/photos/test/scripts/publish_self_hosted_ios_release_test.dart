import "dart:convert";
import "dart:io";

import "package:path/path.dart" as p;
import "package:test/test.dart";

import "../../scripts/prepare_self_hosted_ios_release.dart" as preparation;
import "../../scripts/publish_self_hosted_ios_release.dart";

const _team = "ABCDEFGHIJ";
const _project = "example-project";
const _appId = "1:123:ios:opaque";
const _commit = "0123456789abcdef0123456789abcdef01234567";
const _releaseId = "ente-photos-selfhosted-ios-1.3.59-2159-0123456789ab";

void main() {
  test("parses explicit and environment iOS publication inputs", () {
    final explicit = IOSPublicationOptions.parse(const <String>[
      "--manifest",
      "/tmp/release.manifest.json",
      "--receipt-dir=/tmp/firebase-receipts",
      "--firebase-project",
      _project,
      "--firebase-app=$_appId",
      "--release-notes-file",
      "/tmp/notes.txt",
      "--preflight-only",
    ], environment: const <String, String>{});
    expect(explicit.manifestPath, "/tmp/release.manifest.json");
    expect(explicit.receiptDirectory, "/tmp/firebase-receipts");
    expect(explicit.firebaseProjectId, _project);
    expect(explicit.firebaseAppId, _appId);
    expect(explicit.releaseNotesFile, "/tmp/notes.txt");
    expect(explicit.preflightOnly, isTrue);

    final fromEnvironment = IOSPublicationOptions.parse(
      const <String>[],
      environment: const <String, String>{
        "ENTE_IOS_RELEASE_MANIFEST": "/tmp/release.manifest.json",
        "ENTE_FIREBASE_RELEASE_RECEIPT_DIR": "/tmp/firebase-receipts",
        "ENTE_FIREBASE_PROJECT_ID": _project,
        "ENTE_FIREBASE_IOS_APP_ID": _appId,
      },
    );
    expect(fromEnvironment.firebaseProjectId, _project);
    expect(fromEnvironment.firebaseAppId, _appId);
  });

  test("rejects relative paths and option-like Firebase identifiers", () {
    expect(
      () => IOSPublicationOptions.parse(const <String>[
        "--manifest",
        "release.manifest.json",
        "--receipt-dir",
        "/tmp/receipts",
        "--firebase-project",
        _project,
        "--firebase-app",
        _appId,
      ], environment: const <String, String>{}),
      throwsA(isA<IOSPublicationException>()),
    );
    expect(
      () => IOSPublicationOptions.parse(const <String>[
        "--manifest",
        "/tmp/release.manifest.json",
        "--receipt-dir",
        "/tmp/receipts",
        "--firebase-project",
        "--wrong",
        "--firebase-app",
        _appId,
      ], environment: const <String, String>{}),
      throwsA(isA<IOSPublicationException>()),
    );
  });

  test("validates the exact active Firebase iOS app and group", () {
    final app = validateFirebaseIOSApp(
      firebaseIOSAppsResponse(),
      projectId: _project,
      appId: _appId,
      expectedBundleIdentifier: preparation.expectedBundleIdentifier,
    );
    expect(app["bundleId"], preparation.expectedBundleIdentifier);
    expect(
      () => validateFirebaseIOSApp(
        firebaseIOSAppsResponse(),
        projectId: _project,
        appId: _appId,
        expectedBundleIdentifier: "invalid.bundle",
      ),
      throwsA(isA<IOSPublicationException>()),
    );

    final group = validateFirebaseIOSGroup(
      firebaseIOSGroupsResponse(),
      expectedAlias: trustedIOSTesterGroupAlias,
    );
    expect(group["name"], "projects/123/groups/trusted-ios-testers");
    expect(
      () => validateFirebaseIOSGroup(
        firebaseIOSGroupsResponse(),
        expectedAlias: "wrong-group",
      ),
      throwsA(isA<IOSPublicationException>()),
    );
  });

  test("Firebase client pins the iOS app, group, and notes file", () async {
    final calls = <_ProcessCall>[];
    final runner = _firebaseRunner(calls);
    final client = FirebaseIOSCliClient(
      executable: "/tmp/firebase",
      projectId: _project,
      workingDirectory: "/tmp",
      environment: const <String, String>{
        "PATH": "/usr/bin:/bin",
        "HOME": "/tmp/home",
        "FIREBASE_TOKEN": "must-not-propagate",
        "ENTE_IOS_DISTRIBUTION_TEAM": _team,
        "APPLE_APP_SPECIFIC_PASSWORD": "must-not-propagate",
      },
      runner: runner,
    );

    await client.verifyRegistration(
      appId: _appId,
      expectedBundleIdentifier: preparation.expectedBundleIdentifier,
    );
    await client.distribute(
      ipaPath: "/tmp/release.ipa",
      appId: _appId,
      releaseNotesFile: "/tmp/notes.txt",
    );

    expect(calls, hasLength(3));
    expect(calls.first.arguments.take(2), <String>["apps:list", "IOS"]);
    final upload = calls.last;
    expect(upload.arguments, <String>[
      "appdistribution:distribute",
      "/tmp/release.ipa",
      "--app",
      _appId,
      "--groups",
      trustedIOSTesterGroupAlias,
      "--release-notes-file",
      "/tmp/notes.txt",
      "--project",
      _project,
      "--json",
      "--non-interactive",
    ]);
    expect(upload.arguments, isNot(contains("--testers")));
    for (final call in calls) {
      expect(call.environment["PATH"], "/usr/bin:/bin");
      expect(call.environment["HOME"], "/tmp/home");
      expect(call.environment, isNot(contains("FIREBASE_TOKEN")));
      expect(call.environment, isNot(contains("ENTE_IOS_DISTRIBUTION_TEAM")));
      expect(call.environment, isNot(contains("APPLE_APP_SPECIFIC_PASSWORD")));
    }
  });

  test("generates release notes with one exact AGPL source link", () {
    final prepared = preparedIOSRelease();
    final notes = buildFirebaseIOSReleaseNotes(
      prepared,
      operatorNotes: "Operator-visible change summary.",
    );
    expect(notes, contains("Ente Photos Self-Hosted iOS 1.3.59 (2159)"));
    expect(notes, contains("Source code (AGPL-3.0):"));
    expect(prepared.sourceCommitUrl.allMatches(notes), hasLength(1));
    expect(notes, contains("Operator-visible change summary."));
    expect(
      () => buildFirebaseIOSReleaseNotes(
        prepared,
        operatorNotes: prepared.sourceCommitUrl,
      ),
      throwsA(isA<IOSPublicationException>()),
    );
  });

  test("requires exact confirmation and parses Firebase references", () {
    final expected = confirmationForIOSRelease(_releaseId);
    expect(expected, "PUBLISH $_releaseId");
    expect(
      () => requireExactIOSConfirmation(expected, expected),
      returnsNormally,
    );
    expect(
      () => requireExactIOSConfirmation("yes", expected),
      throwsA(
        isA<IOSPublicationException>().having(
          (error) => error.exitCode,
          "exitCode",
          64,
        ),
      ),
    );

    final references = parseFirebaseIOSReleaseReferences(
      successfulFirebaseUploadOutput,
    );
    expect(references.uploadDisposition, "RELEASE_CREATED");
    expect(
      references.firebaseConsoleUri,
      contains("console.firebase.google.com"),
    );
    expect(
      references.testingUri,
      contains("appdistribution.firebase.google.com"),
    );
    expect(references.binaryDownloadUri, contains("temporary"));
    expect(
      () => parseFirebaseIOSReleaseReferences(
        "View this release in the Firebase console: https://example.com",
      ),
      throwsA(isA<IOSPublicationException>()),
    );
  });

  test("strips Firebase, Apple, signing, and cloud credentials", () {
    final environment =
        sanitizedIOSPublicationEnvironment(const <String, String>{
          "PATH": "/usr/bin:/bin",
          "HOME": "/tmp/home",
          "FIREBASE_CLI": "/tmp/firebase",
          "FIREBASE_TOKEN": "token",
          "GOOGLE_APPLICATION_CREDENTIALS": "/tmp/key.json",
          "ENTE_FIREBASE_IOS_APP_ID": _appId,
          "ENTE_IOS_ADHOC_PROFILE": "/tmp/private.mobileprovision",
          "APPLE_ID": "private@example.invalid",
          "FASTLANE_SESSION": "secret",
          "MATCH_PASSWORD": "secret",
          "AWS_SECRET_ACCESS_KEY": "secret",
          "CUSTOM_PRIVATE_KEY": "secret",
          "SENTRY_AUTH_TOKEN": "secret",
        });
    expect(environment, <String, String>{
      "PATH": "/usr/bin:/bin",
      "HOME": "/tmp/home",
      "FIREBASE_CLI": "/tmp/firebase",
    });
  });

  test("writes immutable receipts and enforces increasing builds", () {
    final root = Directory.systemTemp.createTempSync("ente-ios-receipt-test-");
    try {
      Process.runSync("chmod", ["0700", root.path]);
      final receiptPath = p.join(
        root.path,
        "$_releaseId.firebase-ios-release.json",
      );
      writeImmutableIOSJson(
        receiptPath,
        buildSuccessfulIOSPublicationReceipt(
          prepared: preparedIOSRelease(),
          registration: firebaseIOSRegistration(),
          releaseNotes: "release notes",
          references: firebaseIOSReferences(),
        ),
      );
      expect(File(receiptPath).statSync().mode & 0x1ff, 0x124);
      expect(
        () => writeImmutableIOSJson(receiptPath, <String, Object?>{}),
        throwsA(
          isA<IOSPublicationException>().having(
            (error) => error.exitCode,
            "exitCode",
            73,
          ),
        ),
      );
      expect(
        () => validateIOSPublicationVersionLedger(
          root.path,
          firebaseAppId: _appId,
          bundleIdentifier: preparation.expectedBundleIdentifier,
          buildNumber: 2159,
        ),
        throwsA(isA<IOSPublicationException>()),
      );
      expect(
        () => validateIOSPublicationVersionLedger(
          root.path,
          firebaseAppId: _appId,
          bundleIdentifier: preparation.expectedBundleIdentifier,
          buildNumber: 2160,
        ),
        returnsNormally,
      );
    } finally {
      root.deleteSync(recursive: true);
    }
  });

  test("writes a read-only partial-failure recovery record", () {
    final root = Directory.systemTemp.createTempSync("ente-ios-attempt-test-");
    try {
      Process.runSync("chmod", ["0700", root.path]);
      final path = writeFailedIOSPublicationAttempt(
        root.path,
        prepared: preparedIOSRelease(),
        registration: firebaseIOSRegistration(),
        releaseNotes: "release notes",
        firebaseExitCode: 1,
        firebaseOutput: "upload may have succeeded",
      );
      final value = jsonDecode(File(path).readAsStringSync());
      expect(value["status"], "failed-or-partial");
      expect(value["recovery"], contains("Inspect Firebase"));
      expect(File(path).statSync().mode & 0x1ff, 0x124);
    } finally {
      root.deleteSync(recursive: true);
    }
  });

  test(
    "protects external receipt directories and rejects repository paths",
    () {
      final root = Directory.systemTemp.createTempSync(
        "ente-ios-receipt-directory-test-",
      );
      try {
        final external = prepareExternalIOSReceiptDirectory(
          p.join(root.path, "external-receipts"),
          repositoryRoot: p.join(root.path, "repository"),
        );
        expect(external.statSync().mode & 0x1ff, 0x1c0);
        expect(
          () => prepareExternalIOSReceiptDirectory(
            p.join(root.path, "repository", "receipts"),
            repositoryRoot: p.join(root.path, "repository"),
          ),
          throwsA(isA<IOSPublicationException>()),
        );
      } finally {
        root.deleteSync(recursive: true);
      }
    },
  );

  test("loads the immutable iOS manifest and detects writable bytes", () async {
    final fixture = await _PublisherFixture.create();
    try {
      final prepared = await fixture.loadPrepared();
      expect(prepared.releaseId, _releaseId);
      expect(prepared.ipaSha256, fixture.ipaSha256);
      expect(prepared.teamIdentifier, _team);

      Process.runSync("chmod", ["0644", fixture.ipaPath]);
      expect(
        () => fixture.loadPrepared(),
        throwsA(isA<IOSPublicationException>()),
      );
    } finally {
      fixture.dispose();
    }
  });

  test("rejects a manifest without isolated Rust binding provenance", () async {
    final fixture = await _PublisherFixture.create();
    try {
      Process.runSync("chmod", ["0644", fixture.manifestPath]);
      final manifest =
          jsonDecode(File(fixture.manifestPath).readAsStringSync())
              as Map<String, dynamic>;
      (manifest["build"]
              as Map<String, dynamic>)["rustBindingsGeneratedFromCheckout"] =
          false;
      File(fixture.manifestPath).writeAsStringSync(
        "${const JsonEncoder.withIndent("  ").convert(manifest)}\n",
      );
      Process.runSync("chmod", ["0444", fixture.manifestPath]);

      await expectLater(
        fixture.loadPrepared(),
        throwsA(isA<IOSPublicationException>()),
      );
    } finally {
      fixture.dispose();
    }
  });

  test("preflight re-audits and queries Firebase without uploading", () async {
    final fixture = await _PublisherFixture.create();
    try {
      final calls = <_ProcessCall>[];
      var auditCount = 0;
      final result = await publishSelfHostedIOSRelease(
        fixture.options(preflightOnly: true),
        appDirectoryOverride: fixture.appDirectory,
        processRunner: _firebaseRunner(calls),
        releaseAuditor: (prepared, {required environment}) async {
          auditCount++;
          expect(prepared.ipaSha256, fixture.ipaSha256);
          expect(environment["FIREBASE_CLI"], fixture.firebaseCliPath);
        },
      );
      expect(result, isNull);
      expect(auditCount, 1);
      expect(calls, hasLength(2));
      expect(
        calls.any(
          (call) => call.arguments.first == "appdistribution:distribute",
        ),
        isFalse,
      );
      expect(fixture.receiptDirectory.listSync(followLinks: false), isEmpty);
    } finally {
      fixture.dispose();
    }
  });

  test("publishes only after rechecks and writes a success receipt", () async {
    final fixture = await _PublisherFixture.create();
    try {
      final calls = <_ProcessCall>[];
      var auditCount = 0;
      final result = await publishSelfHostedIOSRelease(
        fixture.options(),
        appDirectoryOverride: fixture.appDirectory,
        processRunner: _firebaseRunner(calls),
        readConfirmation: () => confirmationForIOSRelease(_releaseId),
        releaseAuditor: (prepared, {required environment}) async {
          auditCount++;
        },
      );
      expect(result, isNotNull);
      expect(auditCount, 2);
      expect(calls, hasLength(5));
      expect(
        calls.where(
          (call) => call.arguments.first == "appdistribution:distribute",
        ),
        hasLength(1),
      );
      final receipt = File(result!.receiptPath);
      expect(receipt.existsSync(), isTrue);
      expect(receipt.statSync().mode & 0x1ff, 0x124);
      final value = jsonDecode(receipt.readAsStringSync());
      expect(value["status"], "published");
      expect(value["ios"]["buildNumber"], 2159);
      expect(value["firebase"]["groupAlias"], trustedIOSTesterGroupAlias);
    } finally {
      fixture.dispose();
    }
  });

  test("wrong confirmation prevents every mutating Firebase call", () async {
    final fixture = await _PublisherFixture.create();
    try {
      final calls = <_ProcessCall>[];
      await expectLater(
        publishSelfHostedIOSRelease(
          fixture.options(),
          appDirectoryOverride: fixture.appDirectory,
          processRunner: _firebaseRunner(calls),
          readConfirmation: () => "yes",
          releaseAuditor: (prepared, {required environment}) async {},
        ),
        throwsA(
          isA<IOSPublicationException>().having(
            (error) => error.exitCode,
            "exitCode",
            64,
          ),
        ),
      );
      expect(
        calls.any(
          (call) => call.arguments.first == "appdistribution:distribute",
        ),
        isFalse,
      );
      expect(fixture.receiptDirectory.listSync(followLinks: false), isEmpty);
    } finally {
      fixture.dispose();
    }
  });

  test("post-confirmation IPA changes fail before Firebase mutation", () async {
    final fixture = await _PublisherFixture.create();
    try {
      final calls = <_ProcessCall>[];
      var auditCount = 0;
      await expectLater(
        publishSelfHostedIOSRelease(
          fixture.options(),
          appDirectoryOverride: fixture.appDirectory,
          processRunner: _firebaseRunner(calls),
          readConfirmation: () {
            Process.runSync("chmod", ["0644", fixture.ipaPath]);
            File(fixture.ipaPath).writeAsStringSync("tampered after audit");
            Process.runSync("chmod", ["0444", fixture.ipaPath]);
            return confirmationForIOSRelease(_releaseId);
          },
          releaseAuditor: (prepared, {required environment}) async {
            auditCount++;
          },
        ),
        throwsA(isA<IOSPublicationException>()),
      );
      expect(auditCount, 1);
      expect(
        calls.any(
          (call) => call.arguments.first == "appdistribution:distribute",
        ),
        isFalse,
      );
      expect(fixture.receiptDirectory.listSync(followLinks: false), isEmpty);
    } finally {
      fixture.dispose();
    }
  });

  test(
    "missing success references preserve a partial-attempt receipt",
    () async {
      final fixture = await _PublisherFixture.create();
      try {
        final calls = <_ProcessCall>[];
        await expectLater(
          publishSelfHostedIOSRelease(
            fixture.options(),
            appDirectoryOverride: fixture.appDirectory,
            processRunner: _firebaseRunner(
              calls,
              uploadOutput: "Firebase reported success without references",
            ),
            readConfirmation: () => confirmationForIOSRelease(_releaseId),
            releaseAuditor: (prepared, {required environment}) async {},
          ),
          throwsA(isA<IOSPublicationException>()),
        );
        final attempts = fixture.receiptDirectory
            .listSync(followLinks: false)
            .whereType<File>()
            .where((file) => file.path.contains("firebase-ios-attempt"))
            .toList();
        expect(attempts, hasLength(1));
        expect(attempts.single.statSync().mode & 0x1ff, 0x124);
        expect(
          jsonDecode(attempts.single.readAsStringSync())["status"],
          "failed-or-partial",
        );
      } finally {
        fixture.dispose();
      }
    },
  );

  _registerOptionalRealIpaTests();
}

const successfulFirebaseUploadOutput = """
✔ uploaded new release 1.3.59 (2159) successfully!
✔ View this release in the Firebase console: https://console.firebase.google.com/project/example/release/abc
✔ Share this release with testers who have access: https://appdistribution.firebase.google.com/testerapps/abc
✔ Download the release binary (link expires in 1 hour): https://firebase.example/binary?temporary=1
""";

Map<String, dynamic> firebaseIOSAppsResponse() => <String, dynamic>{
  "status": "success",
  "result": <Object?>[
    <String, Object?>{
      "name": "projects/example-project/iosApps/opaque",
      "appId": _appId,
      "displayName": "Ente Photos Self-Hosted iOS",
      "projectId": _project,
      "bundleId": preparation.expectedBundleIdentifier,
      "state": "ACTIVE",
      "platform": "IOS",
    },
  ],
};

Map<String, dynamic> firebaseIOSGroupsResponse() => <String, dynamic>{
  "status": "success",
  "result": <String, Object?>{
    "groups": <Object?>[
      <String, Object?>{
        "name": "projects/123/groups/trusted-ios-testers",
        "displayName": "Trusted iOS Testers",
      },
    ],
  },
};

PreparedIOSReleaseManifest preparedIOSRelease({
  int buildNumber = 2159,
}) => PreparedIOSReleaseManifest(
  manifestPath: "/tmp/$_releaseId.manifest.json",
  manifestSha256:
      "57d90841070903430374bb4dda3339b737a4980cfafa9659f73e6e2a235c50ae",
  releaseId: _releaseId,
  ipaPath: "/tmp/$_releaseId.ipa",
  ipaSha256: "b4996440a95079b082cc45ca51f707297a9749b41ad6e61074d0fda6b42266fe",
  ipaSizeBytes: 88632015,
  commit: _commit,
  sourceRemote: "https://github.com/vanton1/ente.git",
  sourceCommitUrl: "https://github.com/vanton1/ente/commit/$_commit",
  bundleIdentifier: preparation.expectedBundleIdentifier,
  marketingVersion: "1.3.59",
  buildNumber: buildNumber,
  compiledDefaultEndpoint: "https://museum.example",
  architectures: preparation.expectedArchitectures,
  machOCount: 103,
  signedEntitlementKeys: preparation.expectedSignedEntitlementKeys,
  applicationIdentifier: "$_team.${preparation.expectedBundleIdentifier}",
  teamIdentifier: _team,
  profileName: "Fixture Owner Ad Hoc",
  profileUuid: "01234567-89AB-CDEF-0123-456789ABCDEF",
  profileExpiration: DateTime.utc(2099, 7, 17),
  authorizedDeviceCount: 1,
  signingCertificateSha256: preparation.expectedDistributionCertificateSha256,
  certificateNotBefore: DateTime.utc(2026, 7, 17),
  certificateNotAfter: DateTime.utc(2099, 7, 17),
  deepSignatureStructureValid: true,
  localTrustChainAccepted: false,
  xcodeVersion: "26.6",
  xcodeBuildVersion: "17G86",
);

FirebaseIOSRegistration firebaseIOSRegistration() =>
    const FirebaseIOSRegistration(
      projectId: _project,
      appId: _appId,
      bundleIdentifier: preparation.expectedBundleIdentifier,
      groupName: "projects/123/groups/trusted-ios-testers",
      groupDisplayName: "Trusted iOS Testers",
    );

FirebaseIOSReleaseReferences firebaseIOSReferences() =>
    const FirebaseIOSReleaseReferences(
      firebaseConsoleUri: "https://console.firebase.google.com/release/abc",
      testingUri: "https://appdistribution.firebase.google.com/testerapps/abc",
      binaryDownloadUri: "https://firebase.example/binary?temporary=1",
      uploadDisposition: "RELEASE_CREATED",
    );

IOSPublicationProcessRunner _firebaseRunner(
  List<_ProcessCall> calls, {
  String uploadOutput = successfulFirebaseUploadOutput,
}) {
  return (
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) async {
    calls.add(
      _ProcessCall(
        executable,
        List<String>.from(arguments),
        workingDirectory,
        Map<String, String>.from(environment ?? const {}),
      ),
    );
    if (arguments.first == "apps:list") {
      return ProcessResult(1, 0, jsonEncode(firebaseIOSAppsResponse()), "");
    }
    if (arguments.first == "appdistribution:groups:list") {
      return ProcessResult(2, 0, jsonEncode(firebaseIOSGroupsResponse()), "");
    }
    return ProcessResult(3, 0, "", uploadOutput);
  };
}

class _PublisherFixture {
  _PublisherFixture({
    required this.root,
    required this.repositoryRoot,
    required this.appDirectory,
    required this.releaseDirectory,
    required this.receiptDirectory,
    required this.ipaPath,
    required this.manifestPath,
    required this.ipaSha256,
    required this.firebaseCliPath,
    required this.environment,
  });

  static Future<_PublisherFixture> create() async {
    final root = Directory.systemTemp.createTempSync(
      "ente-ios-publisher-fixture-",
    );
    final repositoryRoot = p.join(root.path, "repository");
    final appDirectory = p.join(repositoryRoot, "mobile", "apps", "photos");
    Directory(appDirectory).createSync(recursive: true);
    final releaseDirectory = Directory(p.join(root.path, "prepared"))
      ..createSync();
    final receiptDirectory = Directory(p.join(root.path, "receipts"))
      ..createSync();
    Process.runSync("chmod", [
      "0700",
      releaseDirectory.path,
      receiptDirectory.path,
    ]);

    final ipaPath = p.join(releaseDirectory.path, "$_releaseId.ipa");
    File(ipaPath).writeAsBytesSync(utf8.encode("fixture IPA bytes"));
    final ipaSha256 = await preparation.sha256File(ipaPath);
    final manifestPath = p.join(
      releaseDirectory.path,
      "$_releaseId.manifest.json",
    );
    final manifest = _manifestValue(
      ipaPath: ipaPath,
      ipaSha256: ipaSha256,
      ipaSizeBytes: File(ipaPath).lengthSync(),
    );
    File(manifestPath).writeAsStringSync(
      "${const JsonEncoder.withIndent("  ").convert(manifest)}\n",
      flush: true,
    );
    Process.runSync("chmod", ["0444", ipaPath, manifestPath]);

    final firebaseCli = File(p.join(root.path, "firebase"))
      ..writeAsStringSync("#!/bin/bash\nexit 99\n");
    Process.runSync("chmod", ["0700", firebaseCli.path]);
    final environment = <String, String>{
      ...Platform.environment,
      "FIREBASE_CLI": firebaseCli.path,
    };
    return _PublisherFixture(
      root: root,
      repositoryRoot: repositoryRoot,
      appDirectory: appDirectory,
      releaseDirectory: releaseDirectory,
      receiptDirectory: receiptDirectory,
      ipaPath: ipaPath,
      manifestPath: manifestPath,
      ipaSha256: ipaSha256,
      firebaseCliPath: firebaseCli.path,
      environment: environment,
    );
  }

  final Directory root;
  final String repositoryRoot;
  final String appDirectory;
  final Directory releaseDirectory;
  final Directory receiptDirectory;
  final String ipaPath;
  final String manifestPath;
  final String ipaSha256;
  final String firebaseCliPath;
  final Map<String, String> environment;

  IOSPublicationOptions options({bool preflightOnly = false}) =>
      IOSPublicationOptions(
        manifestPath: manifestPath,
        receiptDirectory: receiptDirectory.path,
        firebaseProjectId: _project,
        firebaseAppId: _appId,
        environment: environment,
        preflightOnly: preflightOnly,
      );

  Future<PreparedIOSReleaseManifest> loadPrepared() =>
      loadAndValidatePreparedIOSManifest(
        manifestPath,
        repositoryRoot: repositoryRoot,
        environment: environment,
      );

  void dispose() {
    if (root.existsSync()) {
      root.deleteSync(recursive: true);
    }
  }
}

Map<String, Object?> _manifestValue({
  required String ipaPath,
  required String ipaSha256,
  required int ipaSizeBytes,
}) => <String, Object?>{
  "schemaVersion": preparation.releaseManifestSchemaVersion,
  "preparationTool": <String, Object?>{
    "name": preparation.preparationToolName,
    "version": preparation.preparationToolVersion,
    "sourceSha256":
        "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
  },
  "preparedAt": "2026-07-18T10:00:00.000Z",
  "releaseId": _releaseId,
  "artifact": <String, Object?>{
    "fileName": "$_releaseId.ipa",
    "absolutePath": ipaPath,
    "sha256": ipaSha256,
    "sizeBytes": ipaSizeBytes,
  },
  "source": <String, Object?>{
    "commit": _commit,
    "remote": "https://github.com/vanton1/ente.git",
    "commitUrl": "https://github.com/vanton1/ente/commit/$_commit",
    "isolatedCheckout": true,
    "checkoutCleanBeforeBuild": true,
    "checkoutCleanAfterAudit": true,
  },
  "build": <String, Object?>{
    "archiveExportContractVersion": preparation.archiveExportContractVersion,
    "rustBindingsGeneratedFromCheckout": true,
    "scheme": "selfhosted",
    "configuration": "Release-selfhosted",
    "exportMethod": "release-testing",
    "xcodeVersion": "26.6",
    "xcodeBuildVersion": "17G86",
  },
  "ios": <String, Object?>{
    "bundleIdentifier": preparation.expectedBundleIdentifier,
    "marketingVersion": "1.3.59",
    "buildNumber": 2159,
    "buildConfiguration": "release",
    "debuggable": false,
    "compiledDefaultEndpoint": "https://museum.example",
    "architectures": <String>["arm64"],
    "machOCount": 103,
    "extensionCount": 0,
    "signedEntitlementKeys": preparation.expectedSignedEntitlementKeys.toList()
      ..sort(),
    "applicationIdentifier": "$_team.${preparation.expectedBundleIdentifier}",
    "teamIdentifier": _team,
    "profile": <String, Object?>{
      "name": "Fixture Owner Ad Hoc",
      "uuid": "01234567-89AB-CDEF-0123-456789ABCDEF",
      "expiresAt": "2099-07-17T11:30:00.000Z",
      "authorizedDeviceCount": 1,
    },
    "signingCertificate": <String, Object?>{
      "sha256": preparation.expectedDistributionCertificateSha256,
      "notBefore": "2026-07-17T11:30:00.000Z",
      "notAfter": "2099-07-17T11:30:00.000Z",
    },
    "signature": <String, Object?>{
      "deepStructureValid": true,
      "localTrustChainAccepted": false,
    },
  },
};

class _ProcessCall {
  const _ProcessCall(
    this.executable,
    this.arguments,
    this.workingDirectory,
    this.environment,
  );

  final String executable;
  final List<String> arguments;
  final String? workingDirectory;
  final Map<String, String> environment;
}

void _registerOptionalRealIpaTests() {
  final environment = Platform.environment;
  final ipaPath = environment["ENTE_TEST_RELEASE_IPA"];
  if (ipaPath == null) {
    return;
  }

  test(
    "revalidates a real signed IPA through the publication contract",
    () async {
      final appDirectory = Directory.current.resolveSymbolicLinksSync();
      final repositoryRoot = Directory(
        p.dirname(p.dirname(p.dirname(appDirectory))),
      ).resolveSymbolicLinksSync();
      final root = Directory.systemTemp.createTempSync(
        "ente-ios-real-publisher-test-",
      );
      Process.runSync("chmod", ["0700", root.path]);
      try {
        final endpoint = preparation.canonicalizeConfigurableEndpoint(
          environment["ENTE_SELF_HOSTED_ENDPOINT"]!,
        );
        final team = environment["ENTE_IOS_DISTRIBUTION_TEAM"]!;
        final deviceCount = int.parse(
          environment["ENTE_IOS_EXPECTED_DEVICE_COUNT"]!,
        );
        final marketingVersion = environment["ENTE_IOS_MARKETING_VERSION"]!;
        final buildNumber = int.parse(environment["ENTE_IOS_BUILD_NUMBER"]!);
        final tools = preparation.IOSReleaseToolPaths.fromEnvironment(
          environment,
        );
        final audit = await preparation.auditIOSReleaseIpa(
          ipaPath: ipaPath,
          canonicalEndpoint: endpoint,
          expectedTeam: team,
          expectedDeviceCount: deviceCount,
          expectedMarketingVersion: marketingVersion,
          expectedBuildNumber: buildNumber,
          tools: tools,
          processEnvironment: environment,
        );

        final commit = (await Process.run("git", const [
          "rev-parse",
          "HEAD",
        ], workingDirectory: repositoryRoot)).stdout.toString().trim();
        final origin = (await Process.run("git", const [
          "remote",
          "get-url",
          "origin",
        ], workingDirectory: repositoryRoot)).stdout.toString().trim();
        final sourceCommitUrl =
            "${preparation.normalizeGitHubSourceBaseUrl(origin)}/commit/$commit";
        final sourceSha256 = await preparation.sha256File(
          p.join(
            appDirectory,
            "scripts",
            "prepare_self_hosted_ios_release.dart",
          ),
          shasum: tools.shasum,
          environment: environment,
        );
        final xcodeVersion = await preparation.readXcodeVersion(
          tools.xcodebuild,
          environment: environment,
        );
        final finalized = await preparation.finalizePreparedIOSRelease(
          buildIpaPath: ipaPath,
          audit: audit,
          outputDirectory: root.path,
          commit: commit,
          origin: origin,
          sourceCommitUrl: sourceCommitUrl,
          preparationSourceSha256: sourceSha256,
          xcodeVersion: xcodeVersion,
        );
        final prepared = await loadAndValidatePreparedIOSManifest(
          finalized.manifestPath,
          repositoryRoot: repositoryRoot,
          environment: environment,
        );
        await reAuditPreparedIOSIpa(prepared, environment: environment);
        expect(prepared.bundleIdentifier, preparation.expectedBundleIdentifier);
        expect(prepared.buildNumber, buildNumber);
        expect(prepared.authorizedDeviceCount, deviceCount);
        expect(prepared.machOCount, greaterThan(0));

        if (environment["ENTE_TEST_FIREBASE_IOS_PREFLIGHT"] == "1") {
          final receiptDirectory = Directory(p.join(root.path, "receipts"))
            ..createSync();
          final result = await publishSelfHostedIOSRelease(
            IOSPublicationOptions(
              manifestPath: finalized.manifestPath,
              receiptDirectory: receiptDirectory.path,
              firebaseProjectId: environment["ENTE_FIREBASE_PROJECT_ID"]!,
              firebaseAppId: environment["ENTE_FIREBASE_IOS_APP_ID"]!,
              environment: environment,
              preflightOnly: true,
            ),
            appDirectoryOverride: appDirectory,
          );
          expect(result, isNull);
          expect(receiptDirectory.listSync(followLinks: false), isEmpty);
        }
      } finally {
        if (root.existsSync()) {
          root.deleteSync(recursive: true);
        }
      }
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
