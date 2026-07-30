import "dart:async" show unawaited;

import "package:logging/logging.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/events/diff_sync_complete_event.dart";
import "package:photos/events/people_changed_event.dart";
import "package:photos/service_locator.dart" show isLocalGalleryMode;
import "package:photos/services/machine_learning/face_ml/person/person_service.dart";

class PersonFeedbackService {
  static final _logger = Logger("PersonFeedbackService");

  PersonFeedbackService() {
    Bus.instance.on<DiffSyncCompleteEvent>().listen((event) {
      unawaited(syncPersonFeedback());
    });
    Bus.instance.on<PeopleChangedEvent>().listen((event) {
      if (event.type != PeopleEventType.syncDone) {
        _shouldReconcilePeople = true;
      }
    });
  }

  bool _shouldReconcilePeople = false;
  bool _isSyncing = false;

  Future<void> syncPersonFeedback() async {
    if (_isSyncing) {
      return;
    }
    if (isLocalGalleryMode) {
      _logger.finest("Skipping person feedback sync in local gallery mode");
      return;
    }
    _isSyncing = true;
    try {
      if (_shouldReconcilePeople) {
        await PersonService.instance.reconcileClusters();
        Bus.instance.fire(PeopleChangedEvent(type: PeopleEventType.syncDone));
        _shouldReconcilePeople = false;
      } else {
        final didChange = await PersonService.instance
            .fetchRemoteClusterFeedback();
        if (didChange) {
          _logger.info("people: got remote data update");
          Bus.instance.fire(PeopleChangedEvent(type: PeopleEventType.syncDone));
        }
      }
    } finally {
      _isSyncing = false;
    }
  }
}
