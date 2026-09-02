import 'package:flutter_test/flutter_test.dart';
import 'package:photos/module/download/download_error.dart';

void main() {
  group('download decryption failures', () {
    test('are distinguishable from other download failures', () {
      final error = DownloadDecryptionError('encrypted-sha1');

      expect(error, isA<DownloadFailedError>());
      expect(error, isNot(isA<DownloadNoConnectionError>()));
      expect(error.encryptedFileSha1, 'encrypted-sha1');
      expect(error.toString(), 'Failed to decrypt downloaded file');
    });

    test('can be suppressed for an existing caller', () async {
      final result = await handleDownloadDecryptionFailureForCaller<int>(
        Future<int?>.error(DownloadDecryptionError('encrypted-sha1')),
        rethrowDecryptionFailure: false,
      );

      expect(result, isNull);
    });

    test('can be surfaced to a viewer sharing the same download', () async {
      final sharedDownload = Future<int?>.error(
        DownloadDecryptionError('encrypted-sha1'),
      );
      final existingCaller = handleDownloadDecryptionFailureForCaller<int>(
        sharedDownload,
        rethrowDecryptionFailure: false,
      );
      final viewer = handleDownloadDecryptionFailureForCaller<int>(
        sharedDownload,
        rethrowDecryptionFailure: true,
      );

      expect(await existingCaller, isNull);
      await expectLater(
        viewer,
        throwsA(
          isA<DownloadDecryptionError>().having(
            (error) => error.encryptedFileSha1,
            'encryptedFileSha1',
            'encrypted-sha1',
          ),
        ),
      );
    });
  });
}
