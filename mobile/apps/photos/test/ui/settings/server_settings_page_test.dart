import "dart:typed_data";

import "package:dio/dio.dart";
import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:photos/core/network/endpoint_config.dart";
import "package:photos/core/network/endpoint_policy.dart";
import "package:photos/core/network/endpoint_switcher.dart";
import "package:photos/ente_theme_data.dart";
import "package:photos/generated/l10n.dart";
import "package:photos/ui/settings/server/server_settings_page.dart";
import "package:shared_preferences/shared_preferences.dart";

const _activeEndpoint = "https://museum.example";
const _candidateEndpoint = "https://new-museum.example:8443";
const _configurablePolicy = EndpointPolicy(
  mode: EndpointMode.configurable,
  compiledEndpoint: _activeEndpoint,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets("the server link is visible only in configurable mode", (
    tester,
  ) async {
    final configurablePreferences = await _preferences({
      EndpointConfig.bindingKey: _activeEndpoint,
    });
    var tapCount = 0;
    await _pump(
      tester,
      ConfigurableServerLink(
        config: EndpointConfig(
          configurablePreferences,
          policy: _configurablePolicy,
        ),
        onTap: () => tapCount++,
      ),
    );

    expect(
      find.byKey(const ValueKey("configurableServerLink")),
      findsOneWidget,
    );
    expect(find.textContaining(_activeEndpoint), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey("configurableServerLink")));
    expect(tapCount, 1);

    final standardPreferences = await _preferences({});
    await _pump(
      tester,
      ConfigurableServerLink(
        config: EndpointConfig(
          standardPreferences,
          policy: const EndpointPolicy(
            mode: EndpointMode.standard,
            compiledEndpoint: _activeEndpoint,
          ),
        ),
      ),
    );
    expect(find.byKey(const ValueKey("configurableServerLink")), findsNothing);

    final lockedPreferences = await _preferences({
      EndpointConfig.bindingKey: _activeEndpoint,
    });
    await _pump(
      tester,
      ConfigurableServerLink(
        config: EndpointConfig(
          lockedPreferences,
          policy: const EndpointPolicy(
            mode: EndpointMode.locked,
            compiledEndpoint: _activeEndpoint,
          ),
        ),
      ),
    );
    expect(find.byKey(const ValueKey("configurableServerLink")), findsNothing);
  });

  testWidgets("invalid input is rejected without probing or logging out", (
    tester,
  ) async {
    final fixture = await _Fixture.create(accountState: true);
    addTearDown(fixture.close);
    await _pumpPage(tester, fixture, isSignedIn: true);

    await _enterCandidateAndSubmit(tester, "http://museum.example");

    expect(fixture.adapter.lastRequest, isNull);
    expect(fixture.logoutCount, 0);
    expect(fixture.activeBinding, _activeEndpoint);
    expect(
      find.textContaining("endpoint you entered is invalid"),
      findsOneWidget,
    );
  });

  testWidgets("an unreachable server leaves the current account untouched", (
    tester,
  ) async {
    final fixture = await _Fixture.create(
      accountState: true,
      failConnection: true,
    );
    addTearDown(fixture.close);
    await _pumpPage(tester, fixture, isSignedIn: true);

    await _enterCandidateAndSubmit(tester, _candidateEndpoint);

    expect(fixture.logoutCount, 0);
    expect(fixture.activeBinding, _activeEndpoint);
    expect(fixture.preferences.getString("token"), "token");
    expect(find.textContaining("could not be verified"), findsOneWidget);
  });

  testWidgets("the current server is an event-free non-destructive no-op", (
    tester,
  ) async {
    final fixture = await _Fixture.create(accountState: true);
    addTearDown(fixture.close);
    await _pumpPage(tester, fixture, isSignedIn: true);

    await _enterCandidateAndSubmit(tester, _activeEndpoint);

    expect(fixture.logoutCount, 0);
    expect(fixture.activeBinding, _activeEndpoint);
    expect(find.text("This server is already active."), findsOneWidget);
  });

  testWidgets("a signed-in switch names both origins and can be cancelled", (
    tester,
  ) async {
    final fixture = await _Fixture.create(accountState: true);
    addTearDown(fixture.close);
    await _pumpPage(tester, fixture, isSignedIn: true);

    await _enterCandidateAndOpenConfirmation(tester, _candidateEndpoint);

    expect(find.textContaining(_activeEndpoint), findsWidgets);
    expect(find.textContaining(_candidateEndpoint), findsWidgets);
    expect(find.text("Log out and switch"), findsOneWidget);

    await tester.tap(find.byTooltip("Cancel"));
    await tester.pumpAndSettle();

    expect(fixture.logoutCount, 0);
    expect(fixture.completedSwitches, 0);
    expect(fixture.activeBinding, _activeEndpoint);
    expect(fixture.preferences.getString("token"), "token");
  });

  testWidgets("a confirmed signed-in switch logs out before activation", (
    tester,
  ) async {
    final fixture = await _Fixture.create(accountState: true);
    addTearDown(fixture.close);
    await _pumpPage(tester, fixture, isSignedIn: true);

    await _enterCandidateAndOpenConfirmation(tester, _candidateEndpoint);
    await tester.ensureVisible(find.text("Log out and switch"));
    await tester.pump();
    await tester.tap(find.text("Log out and switch"));
    await tester.pumpAndSettle();

    expect(fixture.logoutCount, 1);
    expect(fixture.completedSwitches, 1);
    expect(fixture.preferences.getKeys(), {EndpointConfig.bindingKey});
    expect(fixture.activeBinding, _candidateEndpoint);
  });

  testWidgets(
    "a logged-out switch activates without destructive confirmation",
    (tester) async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.close);
      await _pumpPage(tester, fixture, isSignedIn: false);

      await _enterCandidateAndSubmit(tester, _candidateEndpoint);

      expect(find.text("Change server?"), findsNothing);
      expect(fixture.logoutCount, 0);
      expect(fixture.completedSwitches, 1);
      expect(fixture.activeBinding, _candidateEndpoint);
    },
  );

  testWidgets("an incomplete login is cleared before switching servers", (
    tester,
  ) async {
    final fixture = await _Fixture.create(partialAccountState: true);
    addTearDown(fixture.close);
    await _pumpPage(tester, fixture, isSignedIn: false);

    await _enterCandidateAndOpenConfirmation(tester, _candidateEndpoint);

    expect(fixture.preferences.getString("email"), "person@example.com");
    expect(find.text("Log out and switch"), findsOneWidget);
    await tester.ensureVisible(find.text("Log out and switch"));
    await tester.pump();
    await tester.tap(find.text("Log out and switch"));
    await tester.pumpAndSettle();

    expect(fixture.logoutCount, 1);
    expect(fixture.completedSwitches, 1);
    expect(fixture.preferences.getKeys(), {EndpointConfig.bindingKey});
    expect(fixture.activeBinding, _candidateEndpoint);
  });

  testWidgets("logout failure keeps the old binding and reports recovery", (
    tester,
  ) async {
    final fixture = await _Fixture.create(accountState: true, failLogout: true);
    addTearDown(fixture.close);
    await _pumpPage(tester, fixture, isSignedIn: true);

    await _enterCandidateAndOpenConfirmation(tester, _candidateEndpoint);
    await tester.ensureVisible(find.text("Log out and switch"));
    await tester.pump();
    await tester.tap(find.text("Log out and switch"));
    await tester.pumpAndSettle();

    expect(fixture.logoutCount, 1);
    expect(fixture.completedSwitches, 0);
    expect(fixture.activeBinding, _activeEndpoint);
    expect(fixture.preferences.getString("token"), "token");
    expect(find.textContaining("server was not changed"), findsOneWidget);
  });
}

Future<void> _pumpPage(
  WidgetTester tester,
  _Fixture fixture, {
  required bool isSignedIn,
}) {
  return _pump(
    tester,
    ServerSettingsPage(
      config: fixture.config,
      switcher: fixture.switcher,
      isSignedIn: isSignedIn,
      localLogout: fixture.logout,
      onSwitchComplete: fixture.onSwitchComplete,
    ),
  );
}

Future<void> _pump(WidgetTester tester, Widget home) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: darkThemeData,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: home,
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _enterCandidateAndSubmit(
  WidgetTester tester,
  String candidate,
) async {
  await tester.enterText(find.byType(TextField), candidate);
  await tester.tap(find.byKey(const ValueKey("verifyAndSwitchServerButton")));
  await tester.pumpAndSettle();
}

Future<void> _enterCandidateAndOpenConfirmation(
  WidgetTester tester,
  String candidate,
) async {
  await tester.enterText(find.byType(TextField), candidate);
  await tester.tap(find.byKey(const ValueKey("verifyAndSwitchServerButton")));
  for (var attempt = 0; attempt < 20; attempt++) {
    await tester.pump(const Duration(milliseconds: 100));
    if (find.text("Change server?").evaluate().isNotEmpty) {
      await tester.pump(const Duration(milliseconds: 500));
      return;
    }
  }
}

Future<SharedPreferences> _preferences(Map<String, Object> values) async {
  SharedPreferences.setMockInitialValues(values);
  return SharedPreferences.getInstance();
}

class _Fixture {
  _Fixture._({
    required this.preferences,
    required this.config,
    required this.adapter,
    required this.switcher,
    required this.failLogout,
  });

  static Future<_Fixture> create({
    bool accountState = false,
    bool partialAccountState = false,
    bool failConnection = false,
    bool failLogout = false,
  }) async {
    final preferences = await _preferences({
      EndpointConfig.bindingKey: _activeEndpoint,
      if (accountState) "token": "token",
      if (accountState) "user_id": 1,
      if (partialAccountState) "email": "person@example.com",
    });
    final config = EndpointConfig(preferences, policy: _configurablePolicy);
    final adapter = _ProbeAdapter(failConnection: failConnection);
    final switcher = EndpointSwitcher(
      config,
      probe: EndpointProbe(
        policy: _configurablePolicy,
        httpClientAdapter: adapter,
      ),
    );
    return _Fixture._(
      preferences: preferences,
      config: config,
      adapter: adapter,
      switcher: switcher,
      failLogout: failLogout,
    );
  }

  final SharedPreferences preferences;
  final EndpointConfig config;
  final _ProbeAdapter adapter;
  final EndpointSwitcher switcher;
  final bool failLogout;

  int logoutCount = 0;
  int completedSwitches = 0;

  String? get activeBinding => preferences.getString(EndpointConfig.bindingKey);

  Future<void> logout() async {
    logoutCount++;
    if (failLogout) {
      throw StateError("test logout failure");
    }
    await config.clearPreferencesForLogout();
  }

  void onSwitchComplete() {
    completedSwitches++;
  }

  void close() {
    switcher.close(force: true);
  }
}

class _ProbeAdapter implements HttpClientAdapter {
  _ProbeAdapter({required this.failConnection});

  final bool failConnection;
  RequestOptions? lastRequest;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastRequest = options;
    if (failConnection) {
      throw DioException.connectionError(
        requestOptions: options,
        reason: "test connection failure",
      );
    }
    return ResponseBody.fromString(
      '{"message":"pong"}',
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
