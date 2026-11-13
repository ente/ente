import "dart:async";

import "package:ente_components/ente_components.dart";
import "package:ente_strings/ente_strings.dart";
import "package:flutter/material.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/events/memories_changed_event.dart";
import "package:photos/service_locator.dart";
import "package:photos/services/memory_home_widget_service.dart";

class MemoriesSettingsScreen extends StatefulWidget {
  const MemoriesSettingsScreen({super.key});

  @override
  State<MemoriesSettingsScreen> createState() => _MemoriesSettingsScreenState();
}

class _MemoriesSettingsScreenState extends State<MemoriesSettingsScreen> {
  @override
  Widget build(BuildContext context) {
    final l10n = context.strings;

    return SettingsPageScaffold(
      title: l10n.memories,
      children: [
        MenuComponent(
          title: l10n.showMemories,
          trailing: ToggleSwitchComponent.async(
            value: () => memoriesCacheService.showAnyMemories,
            onChanged: () async {
              await memoriesCacheService.setShowAnyMemories(
                !memoriesCacheService.showAnyMemories,
              );
              if (!memoriesCacheService.showAnyMemories) {
                unawaited(MemoryHomeWidgetService.instance.clearWidget());
              }
              setState(() {});
            },
          ),
        ),
        if (memoriesCacheService.curatedMemoriesOption) ...[
          const SizedBox(height: 8),
          MenuComponent(
            title: l10n.curatedMemories,
            trailing: ToggleSwitchComponent.async(
              value: () => localSettings.isSmartMemoriesEnabled,
              onChanged: () async {
                unawaited(_toggleUpdateMemories());
              },
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _toggleUpdateMemories() async {
    await localSettings.setSmartMemories(!localSettings.isSmartMemoriesEnabled);
    await memoriesCacheService.clearMemoriesCache(fromDisk: false);
    await memoriesCacheService.getMemories();
    Bus.instance.fire(MemoriesChangedEvent());
  }
}
