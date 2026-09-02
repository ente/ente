import 'package:flutter_test/flutter_test.dart';
import 'package:photos/services/device_folder_confirmed_ente_move_queue.dart';
import 'package:photos/services/device_folder_confirmed_move_planner.dart';

void main() {
  test('selects only exact uploaded source rows in the source folder', () {
    final eligible = selectConfirmedMoveLocalIDs(
      requestedLocalIDs: {
        'valid',
        'pending',
        'cloud-only',
        'duplicate',
        'copy',
      },
      sourceFolderID: 'source',
      pendingLocalIDs: {'pending'},
      folderIDsByLocalID: {
        'valid': {'source'},
        'pending': {'source'},
        'duplicate': {'source'},
        'copy': {'source', 'other'},
      },
      uploadedSourceRowCounts: {
        'valid': 1,
        'pending': 1,
        'cloud-only': 1,
        'duplicate': 2,
        'copy': 1,
      },
    );

    expect(eligible, {'valid'});
  });

  test('recovers prepared rows only after full local and cloud validation', () {
    expect(
      resolvePreparedConfirmedMove(
        mappingsValid: true,
        onlyInDestination: true,
        sourceRowCount: 1,
      ),
      ConfirmedMoveQueueDecision.ready,
    );
    expect(
      resolvePreparedConfirmedMove(
        mappingsValid: true,
        onlyInDestination: false,
        sourceRowCount: 1,
      ),
      ConfirmedMoveQueueDecision.defer,
    );
    expect(
      resolvePreparedConfirmedMove(
        mappingsValid: false,
        onlyInDestination: true,
        sourceRowCount: 1,
      ),
      ConfirmedMoveQueueDecision.discard,
    );
  });

  test(
    'ready rows require exact source truth and clean up completed moves',
    () {
      expect(
        resolveReadyConfirmedMove(
          isPendingUpload: true,
          mappingsValid: true,
          onlyInDestination: true,
          sourceRowCount: 1,
          destinationRowCount: 0,
        ),
        ConfirmedMoveQueueDecision.defer,
      );
      expect(
        resolveReadyConfirmedMove(
          isPendingUpload: false,
          mappingsValid: true,
          onlyInDestination: true,
          sourceRowCount: 1,
          destinationRowCount: 0,
        ),
        ConfirmedMoveQueueDecision.ready,
      );
      expect(
        resolveReadyConfirmedMove(
          isPendingUpload: false,
          mappingsValid: true,
          onlyInDestination: true,
          sourceRowCount: 0,
          destinationRowCount: 1,
        ),
        ConfirmedMoveQueueDecision.completed,
      );
      expect(
        resolveReadyConfirmedMove(
          isPendingUpload: false,
          mappingsValid: true,
          onlyInDestination: true,
          sourceRowCount: 2,
          destinationRowCount: 0,
        ),
        ConfirmedMoveQueueDecision.discard,
      );
    },
  );
}
