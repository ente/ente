import "dart:typed_data";

import "package:dio/dio.dart";
import "package:flutter_test/flutter_test.dart";
import "package:photos/core/constants.dart";
import "package:photos/core/network/endpoint_config.dart";
import "package:photos/core/network/endpoint_policy.dart";
import "package:photos/core/network/endpoint_policy_failure_app.dart";
import "package:photos/core/network/ente_interceptor.dart";
import "package:shared_preferences/shared_preferences.dart";

const _lockedEndpoint = "https://museum.example";
const _lockedPolicy = EndpointPolicy(
  isLocked: true,
  compiledEndpoint: _lockedEndpoint,
);
const _normalPolicy = EndpointPolicy(
  isLocked: false,
  compiledEndpoint: kDefaultProductionEndpoint,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group("normal endpoint policy", () {
    test("preserves saved endpoints and legacy normalization", () async {
      final customPreferences = await _preferences({
        EndpointConfig.preferencesKey: "http://localhost:8080",
      });
      expect(
        EndpointConfig(customPreferences, policy: _normalPolicy).endpoint,
        "http://localhost:8080",
      );

      final legacyPreferences = await _preferences({
        EndpointConfig.preferencesKey: kLegacyProductionEndpoint,
      });
      expect(
        EndpointConfig(legacyPreferences, policy: _normalPolicy).endpoint,
        kDefaultProductionEndpoint,
      );
    });

    test("startup does not write a binding", () async {
      final preferences = await _preferences({});

      expect(
        await validateEndpointStartup(preferences, policy: _normalPolicy),
        isNull,
      );
      expect(preferences.containsKey(EndpointConfig.bindingKey), isFalse);
    });

    test("runtime mutation and logout behavior stay unchanged", () async {
      final preferences = await _preferences({"setting": true});
      final config = EndpointConfig(preferences, policy: _normalPolicy);

      await config.setEndpoint("http://localhost:8080");
      expect(config.endpoint, "http://localhost:8080");

      await config.clearPreferencesForLogout();
      expect(preferences.getKeys(), isEmpty);
    });
  });

  group("locked endpoint validation", () {
    test("accepts and canonicalizes one HTTPS origin", () {
      const policy = EndpointPolicy(
        isLocked: true,
        compiledEndpoint: "https://Museum.Example:8443/",
      );

      expect(policy.lockedEndpoint, "https://museum.example:8443");
    });

    test("rejects unsafe or ambiguous build endpoints", () {
      const invalidEndpoints = [
        "",
        " https://museum.example",
        "http://museum.example",
        "https://museum.example/api",
        "https://museum.example?query=yes",
        "https://museum.example#fragment",
        "https://user@museum.example",
        kDefaultProductionEndpoint,
        kLegacyProductionEndpoint,
        "https://api.ente.com:8443",
      ];

      for (final endpoint in invalidEndpoints) {
        final policy = EndpointPolicy(
          isLocked: true,
          compiledEndpoint: endpoint,
        );
        expect(
          () => policy.lockedEndpoint,
          throwsA(isA<EndpointPolicyException>()),
          reason: endpoint,
        );
      }
    });

    test("compiled endpoint takes precedence over saved state", () async {
      final preferences = await _preferences({
        EndpointConfig.preferencesKey: kDefaultProductionEndpoint,
      });

      expect(
        EndpointConfig(preferences, policy: _lockedPolicy).endpoint,
        _lockedEndpoint,
      );
    });
  });

  group("locked endpoint binding", () {
    test("clean startup writes an idempotent binding", () async {
      final preferences = await _preferences({});
      final config = EndpointConfig(preferences, policy: _lockedPolicy);

      await config.validateForStartup();
      await config.validateForStartup();

      expect(preferences.getString(EndpointConfig.bindingKey), _lockedEndpoint);
    });

    test("a matching binding permits existing account state", () async {
      final preferences = await _preferences({
        EndpointConfig.bindingKey: _lockedEndpoint,
        "token": "token",
        "user_id": 1,
      });

      expect(
        await validateEndpointStartup(preferences, policy: _lockedPolicy),
        isNull,
      );
    });

    test("unbound account state fails closed", () async {
      final preferences = await _preferences({"token": "token"});

      final failure = await validateEndpointStartup(
        preferences,
        policy: _lockedPolicy,
      );

      expect(failure?.reason, EndpointPolicyFailureReason.existingAccountState);
      expect(preferences.containsKey(EndpointConfig.bindingKey), isFalse);
    });

    test("unbound or later runtime endpoint state fails closed", () async {
      for (final values in [
        {EndpointConfig.preferencesKey: _lockedEndpoint},
        {
          EndpointConfig.bindingKey: _lockedEndpoint,
          EndpointConfig.preferencesKey: _lockedEndpoint,
        },
      ]) {
        final preferences = await _preferences(values);
        final failure = await validateEndpointStartup(
          preferences,
          policy: _lockedPolicy,
        );

        expect(
          failure?.reason,
          EndpointPolicyFailureReason.existingEndpointState,
        );
      }
    });

    test("a different binding fails closed", () async {
      final preferences = await _preferences({
        EndpointConfig.bindingKey: "https://other.example",
      });

      final failure = await validateEndpointStartup(
        preferences,
        policy: _lockedPolicy,
      );

      expect(
        failure?.reason,
        EndpointPolicyFailureReason.endpointBindingMismatch,
      );
    });

    test("runtime mutation is rejected", () async {
      final preferences = await _preferences({
        EndpointConfig.bindingKey: _lockedEndpoint,
      });
      final config = EndpointConfig(preferences, policy: _lockedPolicy);

      await expectLater(
        config.setEndpoint("https://other.example"),
        throwsA(
          isA<EndpointPolicyException>().having(
            (error) => error.reason,
            "reason",
            EndpointPolicyFailureReason.runtimeMutationNotAllowed,
          ),
        ),
      );
      expect(preferences.containsKey(EndpointConfig.preferencesKey), isFalse);
    });

    test("logout clears account state but preserves the binding", () async {
      final preferences = await _preferences({
        EndpointConfig.bindingKey: _lockedEndpoint,
        "token": "token",
        "user_id": 1,
        "setting": true,
      });
      final config = EndpointConfig(preferences, policy: _lockedPolicy);

      await config.clearPreferencesForLogout();

      expect(preferences.getKeys(), {EndpointConfig.bindingKey});
      expect(preferences.getString(EndpointConfig.bindingKey), _lockedEndpoint);
    });
  });

  group("authenticated Museum requests", () {
    test("origin comparison includes the effective port", () {
      const policy = EndpointPolicy(
        isLocked: true,
        compiledEndpoint: _lockedEndpoint,
      );

      expect(
        () => policy.validateAuthenticatedRequest(
          Uri.parse("https://museum.example:443/ping"),
        ),
        returnsNormally,
      );
      expect(
        () => policy.validateAuthenticatedRequest(
          Uri.parse("https://museum.example:8443/ping"),
        ),
        throwsA(isA<EndpointPolicyException>()),
      );
    });

    test(
      "locked requests stay on origin and do not follow redirects",
      () async {
        final fixture = await _networkFixture(_lockedPolicy);

        await fixture.dio.get("/ping");

        expect(fixture.adapter.lastRequest?.uri.host, "museum.example");
        expect(fixture.adapter.lastRequest?.headers["X-Auth-Token"], "token");
        expect(fixture.adapter.lastRequest?.followRedirects, isFalse);
      },
    );

    test("locked requests reject a different authenticated origin", () async {
      final fixture = await _networkFixture(_lockedPolicy);

      await expectLater(
        fixture.dio.get("https://other.example/ping"),
        throwsA(
          isA<DioException>().having(
            (error) => (error.error as EndpointPolicyException).reason,
            "policy reason",
            EndpointPolicyFailureReason.authenticatedOriginMismatch,
          ),
        ),
      );
      expect(fixture.adapter.lastRequest, isNull);
    });

    test("normal builds retain cross-origin and redirect behavior", () async {
      final fixture = await _networkFixture(_normalPolicy);

      await fixture.dio.get("https://other.example/ping");

      expect(fixture.adapter.lastRequest?.uri.host, "other.example");
      expect(fixture.adapter.lastRequest?.followRedirects, isTrue);
    });
  });

  testWidgets("startup failure renders local recovery instructions", (
    tester,
  ) async {
    const failure = EndpointPolicyException(
      EndpointPolicyFailureReason.endpointBindingMismatch,
      "The stored server binding does not match this build.",
    );

    await tester.pumpWidget(const EndpointPolicyFailureApp(failure: failure));

    expect(find.text("Ente Photos could not start safely"), findsOneWidget);
    expect(
      find.text(
        "This self-hosted build stopped before creating a network client.",
      ),
      findsOneWidget,
    );
    expect(find.text(failure.message), findsOneWidget);
    expect(find.text(failure.recoveryMessage), findsOneWidget);
  });
}

Future<SharedPreferences> _preferences(Map<String, Object> values) async {
  SharedPreferences.setMockInitialValues(values);
  return SharedPreferences.getInstance();
}

Future<_NetworkFixture> _networkFixture(EndpointPolicy policy) async {
  final preferences = await _preferences({});
  final endpointConfig = EndpointConfig(preferences, policy: policy);
  final dio = Dio(BaseOptions(baseUrl: endpointConfig.endpoint));
  final adapter = _RecordingAdapter();
  dio.httpClientAdapter = adapter;
  dio.interceptors.add(
    EnteRequestInterceptor(endpointConfig, tokenProvider: () => "token"),
  );
  return _NetworkFixture(dio, adapter);
}

class _NetworkFixture {
  const _NetworkFixture(this.dio, this.adapter);

  final Dio dio;
  final _RecordingAdapter adapter;
}

class _RecordingAdapter implements HttpClientAdapter {
  RequestOptions? lastRequest;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastRequest = options;
    return ResponseBody.fromString("{}", 200);
  }

  @override
  void close({bool force = false}) {}
}
