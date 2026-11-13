import "package:photos/events/event.dart";

class SocialDataUpdatedEvent extends Event {
  final int? collectionID;
  final bool hasNewComments;
  final bool hasNewReactions;

  SocialDataUpdatedEvent({
    this.collectionID,
    this.hasNewComments = false,
    this.hasNewReactions = false,
  });

  @override
  String get reason =>
      'SocialDataUpdatedEvent{collectionID: $collectionID, comments: $hasNewComments, reactions: $hasNewReactions}';
}
