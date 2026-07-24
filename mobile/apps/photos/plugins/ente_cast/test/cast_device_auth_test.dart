import "dart:async";
import "dart:io";
import "dart:typed_data";

import "package:ente_cast/src/cast/cast_device_auth.dart";
import "package:ente_cast/src/cast/cast_message_codec.dart";
import "package:ente_cast/src/cast/simple_protobuf.dart";
import "package:flutter_test/flutter_test.dart";

void main() {
  test("encodes a SHA-256 challenge with a sender nonce", () {
    final nonce = Uint8List.fromList(List.generate(16, (index) => index));

    expect(encodeCastAuthChallenge(nonce), [10, 20, 18, 16, ...nonce, 24, 1]);
  });

  test("decodes the device credentials from an auth response", () {
    final nonce = Uint8List.fromList(List.filled(16, 7));

    final response = decodeCastAuthResponse(
      _authResponse(
        signature: [1, 2],
        clientCertificate: [3, 4],
        intermediates: [
          [5],
          [6],
        ],
        nonce: nonce,
        hashAlgorithm: 1,
      ),
    );

    expect(response.signature, [1, 2]);
    expect(response.clientAuthCertificate, [3, 4]);
    expect(response.intermediateCertificates, [
      [5],
      [6],
    ]);
    expect(response.senderNonce, nonce);
    expect(response.hashAlgorithm, 1);
  });

  test(
    "verifies the nonce and TLS certificate signed by the receiver",
    () async {
      final nonce = Uint8List.fromList(List.generate(16, (index) => index));
      final envelopes = StreamController<CastEnvelope>.broadcast();
      Map<String, Object?>? verification;
      final authenticator = CastDeviceAuthenticator(
        createNonce: () => nonce,
        verifyCredentials: (arguments) async {
          verification = arguments;
        },
      );
      Uint8List? challenge;

      final authentication = authenticator.authenticate(
        peerCertificate: _FakeCertificate(Uint8List.fromList([8, 9])),
        envelopes: envelopes.stream,
        sendChallenge: (payload) {
          challenge = payload;
          envelopes.add(
            CastEnvelope(
              namespace: castDeviceAuthNamespace,
              payload: null,
              binaryPayload: _authResponse(
                signature: [1],
                clientCertificate: [2],
                intermediates: const [],
                nonce: nonce,
                hashAlgorithm: 1,
              ),
            ),
          );
        },
        flush: () async {},
        timeout: const Duration(seconds: 1),
      );

      await authentication;

      expect(challenge, encodeCastAuthChallenge(nonce));
      expect(verification?["signatureInput"], [...nonce, 8, 9]);
      await envelopes.close();
    },
  );

  test("supports legacy responses that omit the sender nonce", () async {
    final nonce = Uint8List.fromList(List.filled(16, 1));
    final envelopes = StreamController<CastEnvelope>.broadcast();
    Map<String, Object?>? verification;
    final authenticator = CastDeviceAuthenticator(
      createNonce: () => nonce,
      verifyCredentials: (arguments) async {
        verification = arguments;
      },
    );

    final authentication = authenticator.authenticate(
      peerCertificate: _FakeCertificate(Uint8List.fromList([8, 9])),
      envelopes: envelopes.stream,
      sendChallenge: (_) {
        envelopes.add(
          CastEnvelope(
            namespace: castDeviceAuthNamespace,
            payload: null,
            binaryPayload: _authResponse(
              signature: [1],
              clientCertificate: [2],
              intermediates: const [],
              nonce: const [],
              hashAlgorithm: 0,
            ),
          ),
        );
      },
      flush: () async {},
      timeout: const Duration(seconds: 1),
    );

    await authentication;

    expect(verification?["signatureInput"], [8, 9]);
    await envelopes.close();
  });

  test("rejects a mismatched sender nonce", () async {
    final nonce = Uint8List.fromList(List.filled(16, 1));
    final envelopes = StreamController<CastEnvelope>.broadcast();
    final authenticator = CastDeviceAuthenticator(
      createNonce: () => nonce,
      verifyCredentials: (_) async {},
    );

    final authentication = authenticator.authenticate(
      peerCertificate: _FakeCertificate(Uint8List.fromList([1])),
      envelopes: envelopes.stream,
      sendChallenge: (_) {
        envelopes.add(
          CastEnvelope(
            namespace: castDeviceAuthNamespace,
            payload: null,
            binaryPayload: _authResponse(
              signature: [1],
              clientCertificate: [2],
              intermediates: const [],
              nonce: List.filled(16, 2),
              hashAlgorithm: 1,
            ),
          ),
        );
      },
      flush: () async {},
      timeout: const Duration(seconds: 1),
    );

    await expectLater(
      authentication,
      throwsA(isA<CastAuthenticationException>()),
    );
    await envelopes.close();
  });

  test("rejects a TLS certificate valid for more than four days", () async {
    final authenticator = CastDeviceAuthenticator(
      createNonce: () => Uint8List(16),
      verifyCredentials: (_) async {},
    );

    await expectLater(
      authenticator.authenticate(
        peerCertificate: _FakeCertificate(
          Uint8List.fromList([1]),
          endValidity: DateTime.now().add(const Duration(days: 5)),
        ),
        envelopes: const Stream.empty(),
        sendChallenge: (_) {},
        flush: () async {},
        timeout: const Duration(seconds: 1),
      ),
      throwsA(isA<CastAuthenticationException>()),
    );
  });
}

Uint8List _authResponse({
  required List<int> signature,
  required List<int> clientCertificate,
  required List<List<int>> intermediates,
  required List<int> nonce,
  required int hashAlgorithm,
}) {
  final response = ProtoWriter()
    ..writeBytes(1, signature)
    ..writeBytes(2, clientCertificate);
  for (final intermediate in intermediates) {
    response.writeBytes(3, intermediate);
  }
  response
    ..writeBytes(5, nonce)
    ..writeVarint(6, hashAlgorithm);
  return (ProtoWriter()..writeBytes(2, response.takeBytes())).takeBytes();
}

final class _FakeCertificate implements X509Certificate {
  _FakeCertificate(this.der, {DateTime? endValidity})
    : _endValidity = endValidity;

  @override
  final Uint8List der;

  final DateTime? _endValidity;

  @override
  DateTime get endValidity =>
      _endValidity ?? DateTime.now().add(const Duration(days: 1));

  @override
  String get issuer => "issuer";

  @override
  String get pem => "";

  @override
  Uint8List get sha1 => Uint8List(0);

  @override
  DateTime get startValidity =>
      DateTime.now().subtract(const Duration(days: 1));

  @override
  String get subject => "subject";
}
