import "dart:async";

import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import "package:photos/core/configuration.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/events/app_mode_changed_event.dart";
import 'package:photos/service_locator.dart';
import "package:photos/ui/components/banners/get_started_banner.dart";
import "package:photos/ui/home/memories/memories_strip.dart";
import 'package:photos/ui/home/status_bar_widget.dart';

class HeaderWidget extends StatefulWidget {
  const HeaderWidget({super.key});

  @override
  State<HeaderWidget> createState() => _HeaderWidgetState();
}

class _HeaderWidgetState extends State<HeaderWidget> {
  final Logger _logger = Logger("Header");
  late StreamSubscription<AppModeChangedEvent> _appModeChangedEvent;

  @override
  void initState() {
    super.initState();
    _appModeChangedEvent = Bus.instance.on<AppModeChangedEvent>().listen((_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _appModeChangedEvent.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _logger.info("Building header widget");
    final bool showGetStartedBanner =
        isLocalGalleryMode &&
        !localSettings.localGalleryModeEnabledThisSession &&
        !Configuration.instance.hasConfiguredAccount();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const StatusBarWidget(),
        if (showGetStartedBanner) const GetStartedBanner(),
        MemoriesStripWidget(key: ValueKey(isLocalGalleryMode)),
      ],
    );
  }
}
