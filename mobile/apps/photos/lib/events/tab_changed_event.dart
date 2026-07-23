import 'package:photos/events/event.dart';

class TabChangedEvent extends Event {
  final int selectedIndex;
  final TabChangedEventSource source;

  TabChangedEvent(this.selectedIndex, this.source);
}

enum TabChangedEventSource { tabBar, pageView, collectionsPage, backButton }

class TabDoubleTapEvent extends Event {
  final int selectedIndex;

  TabDoubleTapEvent(this.selectedIndex);
}
