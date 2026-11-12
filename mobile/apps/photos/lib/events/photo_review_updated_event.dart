import "package:photos/events/event.dart";
import "package:photos/models/photo_review/photo_review_models.dart";

class PhotoReviewUpdatedEvent extends Event {
  PhotoReviewUpdatedEvent(Iterable<ReviewMonthKey> monthKeys)
    : monthKeys = Set<ReviewMonthKey>.unmodifiable(monthKeys);

  final Set<ReviewMonthKey> monthKeys;
}
