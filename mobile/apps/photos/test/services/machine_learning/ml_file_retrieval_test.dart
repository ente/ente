import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:photos/module/download/download_error.dart';
import 'package:photos/services/machine_learning/ml_exceptions.dart';
import 'package:photos/services/machine_learning/ml_file_retrieval.dart';

void main() {
  group('ML file decryption retries', () {
    test('returns a successful retry for identical ciphertext', () async {
      var attempts = 0;

      final result = await downloadAndLoadFileForMlWithDecryptionRetry(
        () async {
          attempts++;
          if (attempts < 3) {
            throw DownloadDecryptionError('encrypted-sha1');
          }
          return File('decrypted-file');
        },
      );

      expect(attempts, 3);
      expect(result?.path, 'decrypted-file');
    });

    test('turns four identical failures into an expected ML skip', () async {
      var attempts = 0;

      final result = downloadAndLoadFileForMlWithDecryptionRetry(() async {
        attempts++;
        throw DownloadDecryptionError('encrypted-sha1');
      });

      await expectLater(result, throwsA(isA<RepeatedFileDecryptionError>()));
      expect(attempts, 4);
    });

    test('stops retrying when the ciphertext changes', () async {
      var attempts = 0;

      final result = downloadAndLoadFileForMlWithDecryptionRetry(() async {
        attempts++;
        throw DownloadDecryptionError(
          attempts == 1 ? 'first-sha1' : 'second-sha1',
        );
      });

      await expectLater(
        result,
        throwsA(
          isA<DownloadDecryptionError>().having(
            (error) => error.encryptedFileSha1,
            'encryptedFileSha1',
            'second-sha1',
          ),
        ),
      );
      expect(attempts, 2);
    });
  });
}
