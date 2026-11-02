import "dart:async";
import "dart:io";

import "package:dio/dio.dart";
import "package:ente_base/models/accounts.dart";
import "package:flutter/services.dart";
import "package:flutter_test/flutter_test.dart";
import "package:package_info_plus/package_info_plus.dart";
import "package:photos/core/configuration.dart";
import "package:photos/service_locator.dart";
import "package:photos/services/account/user_service.dart";
import "package:photos/src/rust/frb_generated.dart";
import "package:shared_preferences/shared_preferences.dart";

Future<void> initializeAccountsTest(FakeAccountsClient client) async {
  EntePhotosRust.initMock(api: _FakePhotosRustApi(client));
  SharedPreferences.setMockInitialValues({"email": "person@example.com"});
  final preferences = await SharedPreferences.getInstance();
  final dio = Dio(
    BaseOptions(headers: {HttpHeaders.userAgentHeader: "Photos"}),
  );
  ServiceLocator.instance.init(
    preferences,
    dio,
    Dio(),
    Dio(),
    PackageInfo(
      appName: "Photos",
      packageName: "photos",
      version: "1.0.0",
      buildNumber: "1",
    ),
  );
  const pathProvider = MethodChannel("plugins.flutter.io/path_provider");
  final directory = Directory.systemTemp.createTempSync("accounts-test");
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(pathProvider, (call) async => directory.path);
  addTearDown(() => directory.deleteSync(recursive: true));
  try {
    await Configuration.instance.init(preferences);
  } on MissingPluginException catch (_) {}
  await UserService.instance.init();
}

class FakeAccountsClient extends Fake implements AccountsClient {
  final requests = <Map<String, Object>>[];
  Completer<void>? pendingRequest;
  AccountsError? failure;

  @override
  Future<void> sendOtp({
    required String email,
    required String purpose,
    required bool mobile,
  }) async {
    requests.add({"email": email, "purpose": purpose, "mobile": mobile});
    await pendingRequest?.future;
    if (failure != null) throw failure!;
  }

  @override
  Future<AuthResponse> verifyEmail({
    required String email,
    required String code,
    String? source,
  }) async {
    requests.add({"email": email, "code": code});
    throw failure ?? UnimplementedError();
  }
}

class _FakePhotosRustApi extends Fake implements EntePhotosRustApi {
  final AccountsClient client;

  _FakePhotosRustApi(this.client);

  @override
  AccountsClient enteFrbLibAccountsCreateAccountsClient({
    required AccountsClientConfig config,
  }) => client;
}
