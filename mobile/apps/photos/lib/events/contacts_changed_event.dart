import 'package:photos/events/event.dart';

class ContactsChangedEvent extends Event {
  final Set<int>? contactUserIds;

  ContactsChangedEvent({this.contactUserIds});

  bool matchesContactUserId(int? userId) {
    if (userId == null) {
      return false;
    }
    return contactUserIds == null ? true : contactUserIds!.contains(userId);
  }
}
