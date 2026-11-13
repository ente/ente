import "dart:async";
import "dart:io";
import "dart:math";

import "package:ente_cast/src/cast/cast_message_codec.dart";
import "package:ente_cast/src/cast/cast_trust_anchors.dart";
import "package:ente_cast/src/cast/simple_protobuf.dart";
import "package:flutter/services.dart";

const castDeviceAuthNamespace = "urn:x-cast:com.google.cast.tp.deviceauth";
const castPlatformSenderID = "sender-0";
const castPlatformReceiverID = "receiver-0";

const _sha1 = 0;
const _sha256 = 1;
const _nonceLength = 16;
const _maxPeerCertificateLifetime = Duration(days: 4);
const _authChannel = MethodChannel("io.ente.cast/auth");

final class CastAuthenticationException implements Exception {
  const CastAuthenticationException(this.message);

  final String message;

  @override
  String toString() => "Cast authentication failed: $message";
}

final class CastAuthResponse {
  const CastAuthResponse({
    required this.signature,
    required this.clientAuthCertificate,
    required this.intermediateCertificates,
    required this.senderNonce,
    required this.hashAlgorithm,
  });

  final Uint8List signature;
  final Uint8List clientAuthCertificate;
  final List<Uint8List> intermediateCertificates;
  final Uint8List senderNonce;
  final int hashAlgorithm;
}

final class CastDeviceAuthenticator {
  CastDeviceAuthenticator({
    Future<void> Function(Map<String, Object?> arguments)? verifyCredentials,
    Uint8List Function()? createNonce,
  }) : _verifyCredentials = verifyCredentials ?? _verifyNatively,
       _createNonce = createNonce ?? _secureNonce;

  final Future<void> Function(Map<String, Object?> arguments)
  _verifyCredentials;
  final Uint8List Function() _createNonce;

  Future<void> authenticate({
    required X509Certificate peerCertificate,
    required Stream<CastEnvelope> envelopes,
    required void Function(Uint8List payload) sendChallenge,
    required Future<void> Function() flush,
    required Duration timeout,
  }) async {
    _verifyPeerCertificateValidity(peerCertificate);
    final nonce = _createNonce();
    if (nonce.length != _nonceLength) {
      throw const CastAuthenticationException("Invalid sender nonce");
    }

    final responseFuture = envelopes
        .firstWhere(
          (envelope) =>
              envelope.namespace == castDeviceAuthNamespace &&
              envelope.binaryPayload != null,
        )
        .timeout(
          timeout,
          onTimeout: () => throw const CastAuthenticationException(
            "The receiver did not answer the authentication challenge",
          ),
        );
    sendChallenge(encodeCastAuthChallenge(nonce));
    await flush();

    final envelope = await responseFuture;
    final response = decodeCastAuthResponse(envelope.binaryPayload!);
    if (response.senderNonce.isNotEmpty &&
        !_constantTimeEquals(response.senderNonce, nonce)) {
      throw const CastAuthenticationException("Sender nonce mismatch");
    }

    final signatureInput =
        Uint8List(response.senderNonce.length + peerCertificate.der.length)
          ..setRange(0, response.senderNonce.length, response.senderNonce)
          ..setRange(
            response.senderNonce.length,
            response.senderNonce.length + peerCertificate.der.length,
            peerCertificate.der,
          );

    try {
      await _verifyCredentials({
        "clientAuthCertificate": response.clientAuthCertificate,
        "intermediateCertificates": response.intermediateCertificates,
        "signature": response.signature,
        "signatureInput": signatureInput,
        "hashAlgorithm": response.hashAlgorithm,
        "trustAnchors": castTrustAnchors,
      });
    } on PlatformException catch (error) {
      throw CastAuthenticationException(
        error.message ?? "Device credentials were rejected",
      );
    }
  }

  static Future<void> _verifyNatively(Map<String, Object?> arguments) =>
      _authChannel.invokeMethod<void>("verifyDeviceCredentials", arguments);

  static Uint8List _secureNonce() {
    final random = Random.secure();
    return Uint8List.fromList(
      List.generate(_nonceLength, (_) => random.nextInt(256)),
    );
  }

  static void _verifyPeerCertificateValidity(X509Certificate certificate) {
    final now = DateTime.now();
    if (certificate.startValidity.isAfter(now)) {
      throw const CastAuthenticationException(
        "TLS certificate is not valid yet",
      );
    }
    if (certificate.endValidity.isBefore(now)) {
      throw const CastAuthenticationException("TLS certificate has expired");
    }
    if (certificate.endValidity.isAfter(now.add(_maxPeerCertificateLifetime))) {
      throw const CastAuthenticationException(
        "TLS certificate lifetime exceeds four days",
      );
    }
  }
}

Uint8List encodeCastAuthChallenge(Uint8List nonce) {
  if (nonce.length != _nonceLength) {
    throw ArgumentError.value(nonce.length, "nonce", "Must be 16 bytes");
  }
  final challenge = ProtoWriter()
    ..writeBytes(2, nonce)
    ..writeVarint(3, _sha256);
  return (ProtoWriter()..writeBytes(1, challenge.takeBytes())).takeBytes();
}

CastAuthResponse decodeCastAuthResponse(Uint8List payload) {
  Uint8List? responsePayload;
  int? errorType;
  final message = ProtoReader(payload);
  while (message.hasNext) {
    final field = message.readField();
    if (field.number == 2 && field.bytes != null) {
      responsePayload = field.bytes;
    } else if (field.number == 3 && field.bytes != null) {
      final error = ProtoReader(field.bytes!);
      while (error.hasNext) {
        final errorField = error.readField();
        if (errorField.number == 1) {
          errorType = errorField.varint;
        }
      }
    }
  }
  if (errorType != null) {
    throw CastAuthenticationException("Receiver returned error $errorType");
  }
  if (responsePayload == null) {
    throw const CastAuthenticationException(
      "Receiver returned no authentication response",
    );
  }

  Uint8List? signature;
  Uint8List? clientCertificate;
  final intermediateCertificates = <Uint8List>[];
  var senderNonce = Uint8List(0);
  var hashAlgorithm = _sha1;
  final response = ProtoReader(responsePayload);
  while (response.hasNext) {
    final field = response.readField();
    switch (field.number) {
      case 1:
        signature = field.bytes;
      case 2:
        clientCertificate = field.bytes;
      case 3:
        if (field.bytes case final certificate?) {
          intermediateCertificates.add(certificate);
        }
      case 5:
        senderNonce = field.bytes ?? Uint8List(0);
      case 6:
        hashAlgorithm = field.varint ?? _sha1;
    }
  }
  if (signature == null || signature.isEmpty) {
    throw const CastAuthenticationException("Missing device signature");
  }
  if (clientCertificate == null || clientCertificate.isEmpty) {
    throw const CastAuthenticationException(
      "Missing device authentication certificate",
    );
  }
  if (hashAlgorithm != _sha1 && hashAlgorithm != _sha256) {
    throw CastAuthenticationException(
      "Unsupported signature hash algorithm $hashAlgorithm",
    );
  }
  return CastAuthResponse(
    signature: signature,
    clientAuthCertificate: clientCertificate,
    intermediateCertificates: intermediateCertificates,
    senderNonce: senderNonce,
    hashAlgorithm: hashAlgorithm,
  );
}

bool _constantTimeEquals(Uint8List first, Uint8List second) {
  if (first.length != second.length) {
    return false;
  }
  var difference = 0;
  for (var index = 0; index < first.length; index++) {
    difference |= first[index] ^ second[index];
  }
  return difference == 0;
}
