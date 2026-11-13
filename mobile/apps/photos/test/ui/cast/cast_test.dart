import "package:dio/dio.dart";
import "package:ente_cast/ente_cast.dart";
import "package:ente_strings/ente_strings.dart";
import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:package_info_plus/package_info_plus.dart";
import "package:photos/core/network/network.dart";
import "package:photos/ente_theme_data.dart";
import "package:photos/gateways/cast/cast_gateway.dart";
import "package:photos/models/collection/collection.dart";
import "package:photos/service_locator.dart";
import "package:photos/ui/cast/cast.dart";
import "package:shared_preferences/shared_preferences.dart";

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    ServiceLocator.instance.init(
      preferences,
      Dio(),
      Dio(),
      Dio(),
      PackageInfo(
        appName: "Photos",
        packageName: "photos",
        version: "1.0.0",
        buildNumber: "1",
      ),
    );
    await localSettings.setInternalUserDisabled(true);
    // Initialize the flag refresher outside the widget-test fake clock.
    expect(flagService.enableMultiCast, isFalse);
  });

  testWidgets("stop waits for revocation and a failed request can be retried", (
    tester,
  ) async {
    final requests = _RevocationRequests();
    final transport = _FakeCastService(hasActiveSession: true);
    await _pumpCastButton(tester, requests, transport);

    await tester.tap(find.text("Cast"));
    await tester.pumpAndSettle();
    await tester.tap(find.text("No"));
    await tester.pumpAndSettle();
    expect(requests.pending, isEmpty);
    expect(transport.closeCount, 0);

    await tester.tap(find.text("Cast"));
    await tester.pumpAndSettle();
    await tester.tap(find.text("Yes"));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(seconds: 1));

    expect(requests.pending, hasLength(1));
    expect(transport.closeCount, 0);
    expect(find.text("No"), findsNothing);
    expect(find.text("Please wait..."), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.tapAt(const Offset(10, 10));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text("Please wait..."), findsOneWidget);

    requests.fail();
    await tester.pumpAndSettle();
    expect(transport.closeCount, 0);
    expect(find.text("Error"), findsOneWidget);

    await tester.tap(find.text("OK"));
    await tester.pumpAndSettle();
    await tester.tap(find.text("Cast"));
    await tester.pumpAndSettle();
    await tester.tap(find.text("Yes"));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(seconds: 1));
    expect(transport.closeCount, 0);

    requests.succeed();
    await tester.pumpAndSettle();
    expect(transport.closeCount, 1);
    expect(find.text("Stop casting"), findsNothing);
  });

  testWidgets("pairing stays blocked until revocation succeeds after retry", (
    tester,
  ) async {
    final requests = _RevocationRequests();
    final transport = _FakeCastService(hasActiveSession: false);
    await _pumpCastButton(tester, requests, transport);

    await tester.tap(find.text("Cast"));
    await tester.pump(const Duration(seconds: 1));
    expect(requests.pending, hasLength(1));
    expect(find.text("Please wait..."), findsOneWidget);
    expect(find.text("Auto pair"), findsNothing);
    expect(find.text("Pair using code"), findsNothing);

    requests.fail();
    await tester.pumpAndSettle();
    expect(find.text("Error"), findsOneWidget);
    expect(find.text("Pair using code"), findsNothing);

    await tester.tap(find.text("OK"));
    await tester.pumpAndSettle();
    await tester.tap(find.text("Cast"));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text("Pair using code"), findsNothing);

    requests.succeed();
    await tester.pumpAndSettle();
    expect(find.text("Auto pair"), findsOneWidget);
    expect(find.text("Pair using code"), findsOneWidget);
    expect(transport.closeCount, 0);

    await tester.tap(find.text("Pair using code"));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), "ABC123");
    await tester.tap(find.text("Pair"));
    await tester.pump(const Duration(seconds: 1));
    expect(requests.pending, hasLength(1));
    expect(requests.pending.single.$1.method, "GET");
    expect(requests.pending.single.$1.path, "/cast/device-info/ABC123");
    requests.fail();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text("Error"), findsOneWidget);
    await tester.tap(find.text("OK"));
    await tester.pumpAndSettle();
  });
}

Future<void> _pumpCastButton(
  WidgetTester tester,
  _RevocationRequests requests,
  CastService transport,
) async {
  final originalNetworkClient = NetworkClient.instance;
  NetworkClient.instance = _FakeNetworkClient(requests.dio);
  addTearDown(() => NetworkClient.instance = originalNetworkClient);
  await tester.pumpWidget(
    MaterialApp(
      theme: lightThemeData,
      localizationsDelegates: StringsLocalizations.localizationsDelegates,
      supportedLocales: StringsLocalizations.supportedLocales,
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showCastSheet(
              context,
              _FakeCollection(),
              gateway: CastGateway(requests.dio),
              transport: transport,
            ),
            child: const Text("Cast"),
          ),
        ),
      ),
    ),
  );
}

class _RevocationRequests {
  final dio = Dio();
  final pending = <(RequestOptions, RequestInterceptorHandler)>[];

  _RevocationRequests() {
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          pending.add((options, handler));
        },
      ),
    );
  }

  void fail() {
    final (options, handler) = pending.removeAt(0);
    handler.reject(
      DioException(
        requestOptions: options,
        type: DioExceptionType.connectionError,
      ),
    );
  }

  void succeed() {
    final (options, handler) = pending.removeAt(0);
    handler.resolve(Response<void>(requestOptions: options, statusCode: 200));
  }
}

class _FakeCastService extends Fake implements CastService {
  bool hasActiveSession;
  int closeCount = 0;

  _FakeCastService({required this.hasActiveSession});

  @override
  bool get isSupported => true;

  @override
  Map<String, String> getActiveSessions() =>
      hasActiveSession ? {"device": "connected"} : {};

  @override
  Future<void> closeActiveCasts() async {
    closeCount++;
    hasActiveSession = false;
  }
}

class _FakeCollection extends Fake implements Collection {}

class _FakeNetworkClient extends Fake implements NetworkClient {
  @override
  final Dio enteDio;

  _FakeNetworkClient(this.enteDio);
}
