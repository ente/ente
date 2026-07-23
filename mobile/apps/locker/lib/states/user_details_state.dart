import "dart:async";

import "package:ente_accounts/models/user_details.dart";
import "package:ente_accounts/services/user_service.dart";
import "package:ente_events/event_bus.dart";
import "package:ente_events/models/user_details_changed_event.dart";
import "package:flutter/material.dart";
import "package:locker/events/opened_settings_event.dart";
import "package:locker/events/user_details_refresh_event.dart";

class UserDetailsStateWidget extends StatefulWidget {
  final Widget child;

  const UserDetailsStateWidget({required this.child, super.key});

  @override
  State<UserDetailsStateWidget> createState() => UserDetailsStateWidgetState();
}

class UserDetailsStateWidgetState extends State<UserDetailsStateWidget> {
  late UserDetails? _userDetails;
  late StreamSubscription<OpenedSettingsEvent> _openedSettingsEventSubscription;
  late StreamSubscription<UserDetailsChangedEvent>
  _userDetailsChangedSubscription;
  late StreamSubscription<UserDetailsRefreshEvent>
  _userDetailsRefreshEventSubscription;
  bool _isCached = true;

  @override
  void initState() {
    _userDetails = UserService.instance.getCachedUserDetails();
    _openedSettingsEventSubscription = Bus.instance
        .on<OpenedSettingsEvent>()
        .listen((event) {
          _fetchUserDetails();
        });
    _userDetailsChangedSubscription = Bus.instance
        .on<UserDetailsChangedEvent>()
        .listen((event) {
          _refreshFromCache();
        });
    _userDetailsRefreshEventSubscription = Bus.instance
        .on<UserDetailsRefreshEvent>()
        .listen((event) {
          _fetchUserDetails();
        });
    super.initState();
  }

  @override
  void dispose() {
    _openedSettingsEventSubscription.cancel();
    _userDetailsChangedSubscription.cancel();
    _userDetailsRefreshEventSubscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => InheritedUserDetails(
    userDetailsState: this,
    userDetails: _userDetails,
    isCached: _isCached,
    child: widget.child,
  );

  void _fetchUserDetails() async {
    _userDetails = await UserService.instance.getUserDetailsV2(
      memoryCount: true,
      shouldCache: true,
    );
    _isCached = false;
    if (mounted) {
      setState(() {});
    }
  }

  void _refreshFromCache() {
    _userDetails = UserService.instance.getCachedUserDetails();
    if (mounted) {
      setState(() {});
    }
  }
}

class InheritedUserDetails extends InheritedWidget {
  final UserDetailsStateWidgetState userDetailsState;
  final UserDetails? userDetails;
  final bool isCached;

  const InheritedUserDetails({
    super.key,
    required super.child,
    required this.userDetails,
    required this.isCached,
    required this.userDetailsState,
  });

  static InheritedUserDetails? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<InheritedUserDetails>();

  @override
  bool updateShouldNotify(covariant InheritedUserDetails oldWidget) {
    return (userDetails != oldWidget.userDetails) ||
        (isCached != oldWidget.isCached);
  }
}
