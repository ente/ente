import "package:photos/events/event.dart";

class MLConsentChangedEvent extends Event {
  final bool enabled;

  MLConsentChangedEvent(this.enabled);
}
