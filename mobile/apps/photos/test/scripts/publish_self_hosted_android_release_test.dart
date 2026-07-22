import "dart:convert";
import "dart:io";

import "package:flutter_test/flutter_test.dart";
import "package:path/path.dart" as p;

import "../../scripts/prepare_self_hosted_android_release.dart" as preparation;
import "../../scripts/publish_self_hosted_android_release.dart";

void main() {
  test("parses local Firebase publication inputs", () {
    final options = PublicationOptions.parse([
      "--manifest",
      "/tmp/release.manifest.json",
      "--receipt-dir=/tmp/firebase-receipts",
      "--firebase-project",
      "example-project",
      "--firebase-app=1:123:android:opaque",
      "--release-notes-file",
      "/tmp/notes.txt",
      "--preflight-only",
    ], environment: const <String, String>{});

    expect(options.manifestPath, "/tmp/release.manifest.json");
    expect(options.receiptDirectory, "/tmp/firebase-receipts");
    expect(options.firebaseProjectId, "example-project");
    expect(options.firebaseAppId, "1:123:android:opaque");
    expect(options.releaseNotesFile, "/tmp/notes.txt");
    expect(options.preflightOnly, isTrue);

    final reconciliation = PublicationOptions.parse(const <String>[
      "--manifest=/tmp/release.manifest.json",
      "--receipt-dir=/tmp/firebase-receipts",
      "--firebase-project=example-project",
      "--firebase-app=1:123:android:opaque",
      "--reconcile-attempt=/tmp/firebase-receipts/release-attempt.json",
      "--release-evidence=/tmp/firebase-evidence/releases.json",
    ], environment: const <String, String>{});
    expect(reconciliation.isReconciliation, isTrue);
    expect(
      reconciliation.reconciliationAttemptPath,
      "/tmp/firebase-receipts/release-attempt.json",
    );
    expect(
      reconciliation.releaseEvidencePath,
      "/tmp/firebase-evidence/releases.json",
    );
  });

  test("reads publication inputs from the environment", () {
    final options = PublicationOptions.parse(
      const <String>[],
      environment: const <String, String>{
        "ENTE_ANDROID_RELEASE_MANIFEST": "/tmp/release.manifest.json",
        "ENTE_FIREBASE_RELEASE_RECEIPT_DIR": "/tmp/firebase-receipts",
        "ENTE_FIREBASE_PROJECT_ID": "example-project",
        "ENTE_FIREBASE_ANDROID_APP_ID": "opaque-app-id",
      },
    );

    expect(options.firebaseProjectId, "example-project");
    expect(options.firebaseAppId, "opaque-app-id");
  });

  test("rejects relative release paths and option-like Firebase IDs", () {
    expect(
      () => PublicationOptions.parse(const <String>[
        "--manifest",
        "release.manifest.json",
        "--receipt-dir",
        "/tmp/receipts",
        "--firebase-project",
        "project",
        "--firebase-app",
        "app",
      ], environment: const <String, String>{}),
      throwsA(isA<PublicationException>()),
    );
    expect(
      () => PublicationOptions.parse(const <String>[
        "--manifest",
        "/tmp/release.manifest.json",
        "--receipt-dir",
        "/tmp/receipts",
        "--firebase-project",
        "--wrong",
        "--firebase-app",
        "app",
      ], environment: const <String, String>{}),
      throwsA(isA<PublicationException>()),
    );
  });

  test("validates the exact active Firebase Android registration", () {
    final response = firebaseAppsResponse();
    final app = validateFirebaseAndroidApp(
      response,
      projectId: "example-project",
      appId: "1:123:android:opaque",
      expectedPackageName: preparation.expectedPackageName,
    );

    expect(app["packageName"], preparation.expectedPackageName);
    expect(
      () => validateFirebaseAndroidApp(
        response,
        projectId: "example-project",
        appId: "1:123:android:opaque",
        expectedPackageName: "wrong.package",
      ),
      throwsA(isA<PublicationException>()),
    );
  });

  test("validates the pinned trusted tester group", () {
    final group = validateFirebaseGroup(
      firebaseGroupsResponse(),
      expectedAlias: trustedTesterGroupAlias,
    );

    expect(group["name"], "projects/123/groups/trusted-testers");
    expect(
      () => validateFirebaseGroup(
        firebaseGroupsResponse(),
        expectedAlias: "another-group",
      ),
      throwsA(isA<PublicationException>()),
    );
  });

  test(
    "Firebase client uses only the guarded app, group, and notes file",
    () async {
      final calls = <_ProcessCall>[];
      Future<ProcessResult> runner(
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
          return ProcessResult(1, 0, jsonEncode(firebaseAppsResponse()), "");
        }
        if (arguments.first == "appdistribution:groups:list") {
          return ProcessResult(2, 0, jsonEncode(firebaseGroupsResponse()), "");
        }
        return ProcessResult(3, 0, "{\"status\":\"success\"}", "uploaded");
      }

      final client = FirebaseCliClient(
        executable: "/tmp/firebase",
        projectId: "example-project",
        workingDirectory: "/tmp",
        environment: const <String, String>{
          "PATH": "/usr/bin",
          "FIREBASE_TOKEN": "must-not-propagate",
          "SIGNING_STORE_PASSWORD": "must-not-propagate",
          "ANDROID_KEY_PASSWORD": "must-not-propagate",
        },
        runner: runner,
      );
      await client.verifyRegistration(
        appId: "1:123:android:opaque",
        expectedPackageName: preparation.expectedPackageName,
      );
      await client.distribute(
        apkPath: "/tmp/release.apk",
        appId: "1:123:android:opaque",
        releaseNotesFile: "/tmp/notes.txt",
      );

      expect(calls, hasLength(3));
      final upload = calls.last;
      expect(upload.executable, "/tmp/firebase");
      expect(upload.arguments, <String>[
        "appdistribution:distribute",
        "/tmp/release.apk",
        "--app",
        "1:123:android:opaque",
        "--groups",
        trustedTesterGroupAlias,
        "--release-notes-file",
        "/tmp/notes.txt",
        "--project",
        "example-project",
        "--non-interactive",
      ]);
      expect(upload.arguments, isNot(contains("--testers")));
      for (final call in calls) {
        expect(call.workingDirectory, "/tmp");
        expect(call.environment["PATH"], "/usr/bin");
        expect(call.environment, isNot(contains("FIREBASE_TOKEN")));
        expect(call.environment, isNot(contains("SIGNING_STORE_PASSWORD")));
        expect(call.environment, isNot(contains("ANDROID_KEY_PASSWORD")));
      }
    },
  );

  test("generates audited release notes with one exact AGPL source link", () {
    final notes = buildFirebaseReleaseNotes(
      preparedRelease(),
      operatorNotes: "Operator-visible change summary.",
    );

    expect(notes, contains("Ente Photos Self-Hosted 1.3.59 (2158)"));
    expect(notes, contains("Source code (AGPL-3.0):"));
    expect(preparedRelease().sourceCommitUrl.allMatches(notes), hasLength(1));
    expect(notes, contains("Operator-visible change summary."));
  });

  test("rejects operator notes that duplicate the exact source URL", () {
    final prepared = preparedRelease();
    expect(
      () => buildFirebaseReleaseNotes(
        prepared,
        operatorNotes: prepared.sourceCommitUrl,
      ),
      throwsA(isA<PublicationException>()),
    );
  });

  test("requires the exact release-specific confirmation", () {
    final expected = confirmationFor("release-2158");
    expect(expected, "PUBLISH release-2158");
    expect(() => requireExactConfirmation(expected, expected), returnsNormally);
    expect(
      () => requireExactConfirmation("yes", expected),
      throwsA(
        isA<PublicationException>().having(
          (error) => error.exitCode,
          "exitCode",
          64,
        ),
      ),
    );
  });

  test("parses all Firebase release references and upload disposition", () {
    const output = """
✔ uploaded new release 1.3.59 (2158) successfully!
✔ View this release in the Firebase console: https://console.firebase.google.com/project/example/release/abc
✔ Share this release with testers who have access: https://appdistribution.firebase.google.com/testerapps/abc
✔ Download the release binary (link expires in 1 hour): https://firebaseappdistribution.googleapis.com/binary?token=temporary
""";

    final references = parseFirebaseReleaseReferences(output);

    expect(references.uploadDisposition, "RELEASE_CREATED");
    expect(
      references.firebaseConsoleUri,
      contains("console.firebase.google.com"),
    );
    expect(
      references.testingUri,
      contains("appdistribution.firebase.google.com"),
    );
    expect(references.binaryDownloadUri, contains("token=temporary"));
  });

  test("rejects incomplete Firebase success output", () {
    expect(
      () => parseFirebaseReleaseReferences(
        "View this release in the Firebase console: https://example.com",
      ),
      throwsA(isA<PublicationException>()),
    );
  });

  test("writes immutable receipts and blocks non-increasing versions", () {
    final temporaryDirectory = Directory.systemTemp.createTempSync(
      "ente-firebase-receipt-test-",
    );
    try {
      Process.runSync("chmod", ["0700", temporaryDirectory.path]);
      final receiptPath = p.join(
        temporaryDirectory.path,
        "release-2158.firebase-release.json",
      );
      writeImmutableJson(
        receiptPath,
        buildSuccessfulPublicationReceipt(
          prepared: preparedRelease(),
          registration: firebaseRegistration(),
          releaseNotes: "release notes",
          references: firebaseReferences(),
        ),
      );

      expect(File(receiptPath).statSync().mode & 0x1ff, 0x124);
      expect(
        () => writeImmutableJson(receiptPath, <String, Object?>{}),
        throwsA(
          isA<PublicationException>().having(
            (error) => error.exitCode,
            "exitCode",
            73,
          ),
        ),
      );
      expect(
        () => validatePublicationVersionLedger(
          temporaryDirectory.path,
          firebaseAppId: firebaseRegistration().appId,
          packageName: preparation.expectedPackageName,
          versionCode: 2158,
        ),
        throwsA(isA<PublicationException>()),
      );
      expect(
        () => validatePublicationVersionLedger(
          temporaryDirectory.path,
          firebaseAppId: firebaseRegistration().appId,
          packageName: preparation.expectedPackageName,
          versionCode: 2159,
        ),
        returnsNormally,
      );
    } finally {
      temporaryDirectory.deleteSync(recursive: true);
    }
  });

  test("writes a read-only recovery record for partial Firebase failures", () {
    final temporaryDirectory = Directory.systemTemp.createTempSync(
      "ente-firebase-attempt-test-",
    );
    try {
      Process.runSync("chmod", ["0700", temporaryDirectory.path]);
      final path = writeFailedPublicationAttempt(
        temporaryDirectory.path,
        prepared: preparedRelease(),
        registration: firebaseRegistration(),
        releaseNotes: "release notes",
        firebaseExitCode: 1,
        firebaseOutput: "upload may have succeeded",
      );

      final value = jsonDecode(File(path).readAsStringSync());
      expect(value["status"], "failed-or-partial");
      expect(value["recovery"], contains("Inspect Firebase"));
      expect(File(path).statSync().mode & 0x1ff, 0x124);
    } finally {
      temporaryDirectory.deleteSync(recursive: true);
    }
  });

  test(
    "reconciliation preflight validates without upload or receipt",
    () async {
      final fixture = await _PublisherFixture.create();
      try {
        final inputs = await fixture.writeReconciliationInputs();
        final calls = <_ProcessCall>[];
        final result = await reconcileSelfHostedAndroidRelease(
          fixture.options(
            preflightOnly: true,
            reconciliationAttemptPath: inputs.attemptPath,
            releaseEvidencePath: inputs.evidencePath,
          ),
          appDirectoryOverride: fixture.appDirectory,
          processRunner: _firebaseRunner(calls),
          releaseAuditor: (prepared, {required environment}) async {},
        );
        expect(result, isNull);
        expect(calls, hasLength(2));
        expect(
          calls.any(
            (call) => call.arguments.first == "appdistribution:distribute",
          ),
          isFalse,
        );
        expect(
          fixture.receiptDirectory
              .listSync(followLinks: false)
              .whereType<File>()
              .where((file) => file.path.endsWith(".firebase-release.json")),
          isEmpty,
        );
        expect(File(inputs.attemptPath).existsSync(), isTrue);
        expect(File(inputs.evidencePath).existsSync(), isTrue);
      } finally {
        fixture.dispose();
      }
    },
  );

  test("reconciles JSON-only success without a second upload", () async {
    final fixture = await _PublisherFixture.create();
    try {
      final inputs = await fixture.writeReconciliationInputs();
      final calls = <_ProcessCall>[];
      final result = await reconcileSelfHostedAndroidRelease(
        fixture.options(
          reconciliationAttemptPath: inputs.attemptPath,
          releaseEvidencePath: inputs.evidencePath,
        ),
        appDirectoryOverride: fixture.appDirectory,
        processRunner: _firebaseRunner(calls),
        releaseAuditor: (prepared, {required environment}) async {},
      );
      expect(result, isNotNull);
      expect(result!.reconciled, isTrue);
      expect(
        result.references.uploadDisposition,
        "RECONCILED_CLI_JSON_SUCCESS",
      );
      expect(
        calls.any(
          (call) => call.arguments.first == "appdistribution:distribute",
        ),
        isFalse,
      );
      final receipt = File(result.receiptPath);
      expect(receipt.statSync().mode & 0x1ff, 0x124);
      final value = jsonDecode(receipt.readAsStringSync());
      expect(value["status"], "published");
      expect(value["reconciliation"]["noUploadPerformed"], isTrue);
      expect(
        value["firebase"]["uploadDisposition"],
        "RECONCILED_CLI_JSON_SUCCESS",
      );
      expect(File(inputs.attemptPath).existsSync(), isTrue);
      expect(File(inputs.evidencePath).existsSync(), isTrue);
    } finally {
      fixture.dispose();
    }
  });

  test("reconciliation rejects ambiguous official release evidence", () async {
    final fixture = await _PublisherFixture.create();
    try {
      final inputs = await fixture.writeReconciliationInputs();
      final evidence = File(inputs.evidencePath);
      Process.runSync("chmod", ["0644", evidence.path]);
      final value = jsonDecode(evidence.readAsStringSync());
      (value["releases"] as List<Object?>).add(
        Map<String, Object?>.from(
          (value["releases"] as List<Object?>).single! as Map,
        ),
      );
      evidence.writeAsStringSync(jsonEncode(value));
      Process.runSync("chmod", ["0444", evidence.path]);

      await expectLater(
        reconcileSelfHostedAndroidRelease(
          fixture.options(
            reconciliationAttemptPath: inputs.attemptPath,
            releaseEvidencePath: inputs.evidencePath,
          ),
          appDirectoryOverride: fixture.appDirectory,
          processRunner: _firebaseRunner(<_ProcessCall>[]),
          releaseAuditor: (prepared, {required environment}) async {},
        ),
        throwsA(isA<PublicationException>()),
      );
      expect(
        fixture.receiptDirectory
            .listSync(followLinks: false)
            .whereType<File>()
            .where((file) => file.path.endsWith(".firebase-release.json")),
        isEmpty,
      );
    } finally {
      fixture.dispose();
    }
  });

  test("reconciliation rejects mismatched official release bindings", () async {
    final mutations = <void Function(Map<String, dynamic>)>[
      (release) => release["name"] =
          "projects/999/apps/1:999:android:other/releases/foreign",
      (release) => release["displayVersion"] = "9.9.9",
      (release) =>
          release["releaseNotes"] = <String, String>{"text": "different notes"},
      (release) => release["createTime"] = DateTime.now()
          .toUtc()
          .subtract(const Duration(hours: 3))
          .toIso8601String(),
      (release) =>
          release["binaryDownloadUri"] = "https://example.invalid/binary",
    ];
    for (final mutate in mutations) {
      final fixture = await _PublisherFixture.create();
      try {
        final inputs = await fixture.writeReconciliationInputs();
        final evidence = File(inputs.evidencePath);
        Process.runSync("chmod", ["0644", evidence.path]);
        final value = Map<String, dynamic>.from(
          jsonDecode(evidence.readAsStringSync()) as Map,
        );
        final release = Map<String, dynamic>.from(
          (value["releases"] as List<Object?>).single! as Map,
        );
        mutate(release);
        value["releases"] = <Object?>[release];
        evidence.writeAsStringSync(jsonEncode(value));
        Process.runSync("chmod", ["0444", evidence.path]);

        await expectLater(
          reconcileSelfHostedAndroidRelease(
            fixture.options(
              reconciliationAttemptPath: inputs.attemptPath,
              releaseEvidencePath: inputs.evidencePath,
            ),
            appDirectoryOverride: fixture.appDirectory,
            processRunner: _firebaseRunner(<_ProcessCall>[]),
            releaseAuditor: (prepared, {required environment}) async {},
          ),
          throwsA(isA<PublicationException>()),
        );
      } finally {
        fixture.dispose();
      }
    }
  });

  test("rejects a receipt directory inside the repository", () {
    final repository = Directory.systemTemp.createTempSync(
      "ente-firebase-repository-test-",
    );
    try {
      expect(
        () => prepareExternalReceiptDirectory(
          p.join(repository.path, "receipts"),
          repositoryRoot: repository.path,
        ),
        throwsA(isA<PublicationException>()),
      );
    } finally {
      repository.deleteSync(recursive: true);
    }
  });

  test("strips publication and signing credentials from subprocesses", () {
    final environment = sanitizedPublicationEnvironment(const <String, String>{
      "PATH": "/usr/bin",
      "HOME": "/tmp/home",
      "FIREBASE_TOKEN": "token",
      "GOOGLE_APPLICATION_CREDENTIALS": "/tmp/key.json",
      "GOOGLE_APPLICATION_CREDENTIALS_JSON": "json",
      "GOOGLE_CREDENTIALS": "json",
      "GCLOUD_SERVICE_KEY": "json",
      "CLOUDSDK_AUTH_ACCESS_TOKEN": "token",
      "GOOGLE_OAUTH_ACCESS_TOKEN": "token",
      "GOOGLE_GHA_CREDS_PATH": "/tmp/gha.json",
      "SIGNING_KEY_PASSWORD": "secret",
      "MY_KEYSTORE_PASSWORD": "secret",
    });

    expect(environment, <String, String>{
      "PATH": "/usr/bin",
      "HOME": "/tmp/home",
    });
  });

  final integrationManifest =
      Platform.environment["ENTE_TEST_PREPARED_RELEASE_MANIFEST"];
  if (integrationManifest != null) {
    test("revalidates a real prepared release manifest and APK", () async {
      final appDirectory = Directory.current.resolveSymbolicLinksSync();
      final repositoryRoot = Directory(
        p.dirname(p.dirname(p.dirname(appDirectory))),
      ).resolveSymbolicLinksSync();
      final prepared = await loadAndValidatePreparedManifest(
        integrationManifest,
        repositoryRoot: repositoryRoot,
        environment: Platform.environment,
      );
      await reAuditPreparedApk(prepared, environment: Platform.environment);

      expect(prepared.packageName, preparation.expectedPackageName);
      expect(prepared.versionCode, 2158);
      expect(
        prepared.signingCertificateSha256,
        preparation.expectedSigningCertificateSha256,
      );
    });
  }
}

Map<String, dynamic> firebaseAppsResponse() => <String, dynamic>{
  "status": "success",
  "result": <Object?>[
    <String, Object?>{
      "name": "projects/example-project/androidApps/opaque",
      "appId": "1:123:android:opaque",
      "displayName": "Ente Photos Self-Hosted Android",
      "projectId": "example-project",
      "packageName": preparation.expectedPackageName,
      "state": "ACTIVE",
      "platform": "ANDROID",
    },
  ],
};

Map<String, dynamic> firebaseGroupsResponse() => <String, dynamic>{
  "status": "success",
  "result": <String, Object?>{
    "groups": <Object?>[
      <String, Object?>{
        "name": "projects/123/groups/trusted-testers",
        "displayName": "Trusted testers",
      },
    ],
  },
};

PublicationProcessRunner _firebaseRunner(List<_ProcessCall> calls) {
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
      return ProcessResult(1, 0, jsonEncode(firebaseAppsResponse()), "");
    }
    if (arguments.first == "appdistribution:groups:list") {
      return ProcessResult(2, 0, jsonEncode(firebaseGroupsResponse()), "");
    }
    return ProcessResult(3, 0, "", "unexpected mutation");
  };
}

class _PublisherFixture {
  _PublisherFixture({
    required this.root,
    required this.appDirectory,
    required this.releaseDirectory,
    required this.receiptDirectory,
    required this.apkPath,
    required this.manifestPath,
    required this.environment,
  });

  static Future<_PublisherFixture> create() async {
    final root = Directory.systemTemp.createTempSync(
      "ente-android-publisher-fixture-",
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

    final releaseId = preparedRelease().releaseId;
    final apkPath = p.join(releaseDirectory.path, "$releaseId.apk");
    File(apkPath).writeAsBytesSync(utf8.encode("fixture APK bytes"));
    final apkSha256 = await preparation.sha256File(apkPath);
    final manifestPath = p.join(
      releaseDirectory.path,
      "$releaseId.manifest.json",
    );
    final manifest = _manifestValue(
      apkPath: apkPath,
      apkSha256: apkSha256,
      apkSizeBytes: File(apkPath).lengthSync(),
    );
    File(manifestPath).writeAsStringSync(
      "${const JsonEncoder.withIndent("  ").convert(manifest)}\n",
      flush: true,
    );
    Process.runSync("chmod", ["0444", apkPath, manifestPath]);

    final firebaseCli = File(p.join(root.path, "firebase"))
      ..writeAsStringSync("#!/bin/bash\nexit 99\n");
    Process.runSync("chmod", ["0700", firebaseCli.path]);
    final buildTools = Directory(
      p.join(root.path, "android-sdk", "build-tools", "fixture"),
    )..createSync(recursive: true);
    for (final name in const <String>["aapt2", "apksigner"]) {
      File(p.join(buildTools.path, name)).writeAsStringSync("");
    }
    final environment = <String, String>{
      ...Platform.environment,
      "FIREBASE_CLI": firebaseCli.path,
      "ANDROID_HOME": p.join(root.path, "android-sdk"),
    };
    return _PublisherFixture(
      root: root,
      appDirectory: appDirectory,
      releaseDirectory: releaseDirectory,
      receiptDirectory: receiptDirectory,
      apkPath: apkPath,
      manifestPath: manifestPath,
      environment: environment,
    );
  }

  final Directory root;
  final String appDirectory;
  final Directory releaseDirectory;
  final Directory receiptDirectory;
  final String apkPath;
  final String manifestPath;
  final Map<String, String> environment;

  PublicationOptions options({
    bool preflightOnly = false,
    String? reconciliationAttemptPath,
    String? releaseEvidencePath,
  }) => PublicationOptions(
    manifestPath: manifestPath,
    receiptDirectory: receiptDirectory.path,
    firebaseProjectId: "example-project",
    firebaseAppId: "1:123:android:opaque",
    environment: environment,
    preflightOnly: preflightOnly,
    reconciliationAttemptPath: reconciliationAttemptPath,
    releaseEvidencePath: releaseEvidencePath,
  );

  Future<({String attemptPath, String evidencePath})>
  writeReconciliationInputs() async {
    final prepared = await loadAndValidatePreparedManifest(
      manifestPath,
      repositoryRoot: p.dirname(p.dirname(p.dirname(appDirectory))),
      environment: environment,
    );
    final releaseNotes = buildFirebaseReleaseNotes(prepared);
    final attemptPath = writeFailedPublicationAttempt(
      receiptDirectory.path,
      prepared: prepared,
      registration: firebaseRegistration(),
      releaseNotes: releaseNotes,
      firebaseExitCode: 0,
      firebaseOutput: jsonEncode(<String, String>{"status": "success"}),
    );
    final evidenceDirectory = Directory(p.join(root.path, "evidence"))
      ..createSync();
    Process.runSync("chmod", ["0700", evidenceDirectory.path]);
    final evidencePath = p.join(evidenceDirectory.path, "releases.json");
    final evidence = <String, Object?>{
      "releases": <Object?>[
        <String, Object?>{
          "name":
              "projects/123/apps/1:123:android:opaque/releases/official-release",
          "releaseNotes": <String, String>{"text": releaseNotes},
          "displayVersion": prepared.versionName,
          "buildVersion": prepared.versionCode.toString(),
          "createTime": DateTime.now()
              .toUtc()
              .subtract(const Duration(seconds: 30))
              .toIso8601String(),
          "firebaseConsoleUri":
              "https://console.firebase.google.com/project/example/release/abc",
          "testingUri":
              "https://appdistribution.firebase.google.com/testerapps/abc",
          "binaryDownloadUri":
              "https://firebaseappdistribution.googleapis.com/binary?temporary=1",
        },
      ],
    };
    File(evidencePath).writeAsStringSync(
      "${const JsonEncoder.withIndent("  ").convert(evidence)}\n",
      flush: true,
    );
    Process.runSync("chmod", ["0444", evidencePath]);
    return (attemptPath: attemptPath, evidencePath: evidencePath);
  }

  void dispose() {
    if (root.existsSync()) {
      root.deleteSync(recursive: true);
    }
  }
}

Map<String, Object?> _manifestValue({
  required String apkPath,
  required String apkSha256,
  required int apkSizeBytes,
}) {
  final prepared = preparedRelease();
  return <String, Object?>{
    "schemaVersion": preparation.releaseManifestSchemaVersion,
    "preparationTool": <String, Object?>{
      "name": preparation.preparationToolName,
      "version": preparation.preparationToolVersion,
    },
    "releaseId": prepared.releaseId,
    "artifact": <String, Object?>{
      "fileName": "${prepared.releaseId}.apk",
      "absolutePath": apkPath,
      "sha256": apkSha256,
      "sizeBytes": apkSizeBytes,
    },
    "source": <String, Object?>{
      "commit": prepared.commit,
      "remote": prepared.sourceRemote,
      "commitUrl": prepared.sourceCommitUrl,
      "worktreeClean": true,
    },
    "android": <String, Object?>{
      "packageName": prepared.packageName,
      "versionName": prepared.versionName,
      "versionCode": prepared.versionCode,
      "buildType": "release",
      "debuggable": false,
      "minSdk": prepared.minSdk,
      "targetSdk": prepared.targetSdk,
      "compileSdk": prepared.compileSdk,
      "abis": prepared.abis.toList()..sort(),
      "compiledDefaultEndpoint": prepared.compiledDefaultEndpoint,
      "signingCertificateSha256": prepared.signingCertificateSha256,
      "signatureSchemes": prepared.signatureSchemes,
    },
  };
}

PreparedReleaseManifest preparedRelease({int versionCode = 2158}) {
  const commit = "0123456789abcdef0123456789abcdef01234567";
  const sha256 =
      "57d90841070903430374bb4dda3339b737a4980cfafa9659f73e6e2a235c50ae";
  return PreparedReleaseManifest(
    manifestPath: "/tmp/release.manifest.json",
    manifestSha256: sha256,
    releaseId: "ente-photos-selfhosted-1.3.59-$versionCode-0123456789ab",
    apkPath: "/tmp/release.apk",
    apkSha256: sha256,
    apkSizeBytes: 262750609,
    commit: commit,
    sourceRemote: "https://github.com/vanton1/ente.git",
    sourceCommitUrl: "https://github.com/vanton1/ente/commit/$commit",
    packageName: preparation.expectedPackageName,
    versionName: "1.3.59",
    versionCode: versionCode,
    minSdk: preparation.expectedMinSdk,
    targetSdk: preparation.expectedTargetSdk,
    compileSdk: preparation.expectedCompileSdk,
    abis: preparation.expectedAbis,
    compiledDefaultEndpoint: "https://museum.example",
    signingCertificateSha256: preparation.expectedSigningCertificateSha256,
    signatureSchemes: const <String, bool>{"v2": true},
  );
}

FirebaseRegistration firebaseRegistration() => const FirebaseRegistration(
  projectId: "example-project",
  appId: "1:123:android:opaque",
  packageName: preparation.expectedPackageName,
  groupName: "projects/123/groups/trusted-testers",
  groupDisplayName: "Trusted testers",
);

FirebaseReleaseReferences firebaseReferences() =>
    const FirebaseReleaseReferences(
      firebaseConsoleUri: "https://console.firebase.google.com/release/abc",
      testingUri: "https://appdistribution.firebase.google.com/testerapps/abc",
      binaryDownloadUri: "https://firebase.example/binary?temporary=1",
      uploadDisposition: "RELEASE_CREATED",
    );

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
