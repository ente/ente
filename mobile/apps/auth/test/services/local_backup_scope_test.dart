import 'package:ente_auth/services/local_backup_service.dart';
import 'package:flutter_test/flutter_test.dart';

// Every profile backs up to the same destination and retention keeps only the
// newest few files there, so a file has to say which vault wrote it. Otherwise
// whichever vault backs up last evicts the others' backups.
void main() {
  group('backupFileScopeSegment', () {
    test('the legacy scope has no segment', () {
      expect(backupFileScopeSegment(""), isEmpty);
    });

    test('a scoped profile drops the trailing separator', () {
      expect(backupFileScopeSegment("acct_1."), "acct_1");
      expect(backupFileScopeSegment("acct_12."), "acct_12");
    });
  });

  group('isBackupFileName', () {
    test('recognises every backup flavour, scoped or not', () {
      expect(
        isBackupFileName('ente-auth-daily-backup-2026-07-26_09-00-00.json'),
        isTrue,
      );
      expect(
        isBackupFileName(
          'ente-auth-manual-backup-acct_1-2026-07-26_09-00-00.json',
        ),
        isTrue,
      );
      expect(
        isBackupFileName('ente-auth-auto-backup-2026-07-26_09-00-00.json'),
        isTrue,
      );
    });

    test('ignores unrelated files', () {
      expect(isBackupFileName('ente-auth-export.json'), isFalse);
      expect(isBackupFileName('notes.txt'), isFalse);
    });
  });

  group('backupFileBelongsToScope', () {
    const legacyFile = 'ente-auth-daily-backup-2026-07-26_09-00-00.json';
    const firstFile = 'ente-auth-daily-backup-acct_1-2026-07-26_09-00-00.json';
    const secondFile = 'ente-auth-manual-backup-acct_2-2026-07-26_09-00-00.json';

    test('the legacy scope owns the unsegmented names it always wrote', () {
      expect(backupFileBelongsToScope(legacyFile, ""), isTrue);
    });

    test('a scoped profile owns only its own files', () {
      expect(backupFileBelongsToScope(firstFile, "acct_1."), isTrue);
      expect(backupFileBelongsToScope(secondFile, "acct_2."), isTrue);
      expect(backupFileBelongsToScope(secondFile, "acct_1."), isFalse);
    });

    test('neither scope claims the other\'s backups', () {
      expect(backupFileBelongsToScope(firstFile, ""), isFalse);
      expect(backupFileBelongsToScope(legacyFile, "acct_1."), isFalse);
    });

    test('a similarly named scope is not a prefix match', () {
      const eleventh =
          'ente-auth-daily-backup-acct_11-2026-07-26_09-00-00.json';
      expect(backupFileBelongsToScope(eleventh, "acct_1."), isFalse);
      expect(backupFileBelongsToScope(eleventh, "acct_11."), isTrue);
    });

    test('non backup files belong to nobody', () {
      expect(backupFileBelongsToScope('notes.txt', ""), isFalse);
      expect(backupFileBelongsToScope('notes.txt', "acct_1."), isFalse);
    });
  });
}
