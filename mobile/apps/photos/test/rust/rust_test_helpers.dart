import 'dart:typed_data';

import 'package:photos/src/rust/third_party/ente_frb_lib/session.dart';

Session openTestSession(int port) => openSession(
  input: OpenSessionInput(
    baseUrl: 'http://127.0.0.1:$port',
    authToken: 'test-token',
    userId: 1,
    masterKey: Uint8List(32),
    keyAttributes: const SessionKeyAttributes(
      publicKey: 'pOCSkrZRwni5dyxWn1+puxPZBrRqtoyd+dwrRAn4ogk=',
      encryptedSecretKey:
          '+X2V/HMj8w3AXsDR/40cCYKhGG+xIjoYEY1fhrVki/8lsbbYnoppV9livaNsC7WX',
      secretKeyDecryptionNonce: 'AgICAgICAgICAgICAgICAgICAgICAgIC',
      recoveryKeyEncryptedWithMasterKey:
          'jok1oUB0jgsas9Ske6QuwF0e3qieBz+U7/ls4H+8IvoAiqgtr2AGgrqU4SSFwV4F',
      recoveryKeyDecryptionNonce: 'BAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQE',
    ),
  ),
);
