import 'dart:async';

import 'package:flutter/material.dart';
import 'package:photos/core/event_bus.dart';
import 'package:photos/events/opened_settings_event.dart';
import 'package:photos/events/user_details_changed_event.dart';
import 'package:photos/models/user_details.dart';
import 'package:photos/service_locator.dart';
import 'package:photos/services/account/user_service.dart';

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
    super.initState();
  }

  @override
  void dispose() {
    _openedSettingsEventSubscription.cancel();
    _userDetailsChangedSubscription.cancel();
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
    if (isLocalGalleryMode) return;
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
